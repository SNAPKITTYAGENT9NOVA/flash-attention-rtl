#include "l2_alp.h"

#include <stdio.h>
#include <string.h>

#include "cs_sha256.h"

#define ALP_MAX_FILE (1u << 20)

static int ident_char(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
           c == '_' || c == '\'';
}

size_t alp_scan_sorries(const char *text, size_t len)
{
    size_t count = 0, i = 0;
    unsigned depth = 0;                       /* block comment nesting */
    while (i < len) {
        char c = text[i];
        if (depth > 0) {
            if (c == '/' && i + 1 < len && text[i + 1] == '-') { depth++; i += 2; }
            else if (c == '-' && i + 1 < len && text[i + 1] == '/') { depth--; i += 2; }
            else i++;
            continue;
        }
        if (c == '/' && i + 1 < len && text[i + 1] == '-') { depth = 1; i += 2; continue; }
        if (c == '-' && i + 1 < len && text[i + 1] == '-') {
            while (i < len && text[i] != '\n') i++;
            continue;
        }
        if (c == '"') {
            i++;
            while (i < len && text[i] != '"') i += (text[i] == '\\' && i + 1 < len) ? 2 : 1;
            i++;
            continue;
        }
        if (ident_char(c)) {
            size_t j = i;
            while (j < len && ident_char(text[j])) j++;
            if (j - i == 5 && memcmp(text + i, "sorry", 5) == 0) count++;
            i = j;
            continue;
        }
        i++;
    }
    return count;
}

void alp_init(alp_registry *r) { memset(r, 0, sizeof *r); }

static alp_claim *find(const alp_registry *r, const char *name)
{
    for (size_t i = 0; i < r->count; i++)
        if (strcmp(r->claims[i].name, name) == 0) return (alp_claim *)&r->claims[i];
    return NULL;
}

static cs_status valid_name(const char *name)
{
    if (!name || name[0] == '\0') return CS_ERR_ARG;
    for (size_t i = 0; name[i]; i++) {
        if (i + 1 >= ALP_NAME_MAX) return CS_ERR_ARG;
        if (name[i] == ' ' || name[i] == '\n') return CS_ERR_ARG;     /* keeps the manifest parseable */
    }
    return CS_OK;
}

cs_status alp_declare(alp_registry *r, const char *name)
{
    if (!r) return CS_ERR_ARG;
    cs_status s = valid_name(name);
    if (s != CS_OK) return s;
    if (find(r, name)) return CS_OK;
    if (r->count == ALP_MAX_CLAIMS) return CS_ERR_NOMEM;
    alp_claim *c = &r->claims[r->count++];
    memset(c, 0, sizeof *c);
    strcpy(c->name, name);
    c->state = ALP_MISSING;
    return CS_OK;
}

cs_status alp_attach_proof(alp_registry *r, const char *name, const char *text, size_t len)
{
    if (!r || (!text && len)) return CS_ERR_ARG;
    cs_status s = alp_declare(r, name);
    if (s != CS_OK) return s;
    alp_claim *c = find(r, name);
    c->sorries = alp_scan_sorries(text ? text : "", len);
    c->proof_len = len;
    cs_sha256(text ? text : "", len, c->proof_hash);
    c->state = c->sorries == 0 ? ALP_PROVEN : ALP_SORRY;
    return CS_OK;
}

cs_status alp_attach_file(alp_registry *r, const char *name, const char *path)
{
    if (!r || !path) return CS_ERR_ARG;
    FILE *f = fopen(path, "rb");
    if (!f) return CS_ERR_IO;
    static char buf[ALP_MAX_FILE + 1];
    size_t n = fread(buf, 1, ALP_MAX_FILE + 1, f);
    int bad = ferror(f) || n > ALP_MAX_FILE;
    fclose(f);
    if (bad) return CS_ERR_IO;
    return alp_attach_proof(r, name, buf, n);
}

alp_state alp_state_of(const alp_registry *r, const char *name)
{
    const alp_claim *c = (r && name) ? find(r, name) : NULL;
    return c ? c->state : ALP_MISSING;
}

int alp_proof_available(const alp_registry *r, const char *name)
{
    return alp_state_of(r, name) == ALP_PROVEN;
}

cs_status alp_require(const alp_registry *r, const char *name)
{
    return alp_proof_available(r, name) ? CS_OK : CS_ERR_UNPROVEN;
}

cs_status alp_verify_proof(const alp_registry *r, const char *name, const char *text, size_t len)
{
    if (!r || !name || (!text && len)) return CS_ERR_ARG;
    const alp_claim *c = find(r, name);
    if (!c || c->state == ALP_MISSING) return CS_ERR_UNPROVEN;
    uint8_t h[32];
    cs_sha256(text ? text : "", len, h);
    return (len == c->proof_len && cs_ct_equal(h, c->proof_hash, 32)) ? CS_OK : CS_ERR_TAMPER;
}

size_t alp_total_sorries(const alp_registry *r)
{
    size_t n = 0;
    for (size_t i = 0; i < r->count; i++) n += r->claims[i].sorries;
    return n;
}

size_t alp_manifest(const alp_registry *r, char *buf, size_t cap)
{
    static const char *names[] = {"missing", "proven", "sorry"};
    size_t total = 0;
    char line[256];
    int n = snprintf(line, sizeof line, "alp-manifest v1\n");
    for (size_t i = 0; ; i++) {
        if (i > 0) {
            if (i > r->count + 1) break;
            if (i <= r->count) {
                const alp_claim *c = &r->claims[i - 1];
                char hex[65];
                cs_hex(c->proof_hash, 32, hex);
                n = snprintf(line, sizeof line, "%s %s sorries=%zu sha256=%s\n", c->name,
                             names[c->state], c->sorries, c->state == ALP_MISSING ? "-" : hex);
            } else {
                n = snprintf(line, sizeof line, "total_sorries=%zu\n", alp_total_sorries(r));
            }
        }
        if (cap > 0 && total < cap) {
            size_t room = cap - total - 1;
            size_t w = (size_t)n < room ? (size_t)n : room;
            memcpy(buf + total, line, w);
            buf[total + w] = '\0';
        }
        total += (size_t)n;
    }
    return total;
}
