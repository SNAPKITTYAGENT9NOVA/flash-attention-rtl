#include "l8_worm.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "cs_sha256.h"

static void genesis(uint8_t out[32])
{
    cs_sha256("cstack-worm-genesis-v1", 22, out);
}

static void next_seal(uint64_t index, const uint8_t prev[32], const uint8_t witness[32], uint8_t out[32])
{
    cs_sha256_ctx c;
    cs_sha256_init(&c);
    cs_sha256_update(&c, "cstack-worm-seal-v1", 19);
    cs_sha256_update_u64(&c, index);
    cs_sha256_update(&c, prev, 32);
    cs_sha256_update(&c, witness, 32);
    cs_sha256_final(&c, out);
}

cs_status worm_verify_chain(const worm_seal *seals, size_t n)
{
    if (!seals || n == 0) return CS_ERR_TAMPER;
    uint8_t g[32], zero[32] = {0};
    genesis(g);
    if (seals[0].index != 0 || !cs_ct_equal(seals[0].seal, g, 32) ||
        !cs_ct_equal(seals[0].witness_digest, zero, 32))
        return CS_ERR_TAMPER;
    for (size_t i = 1; i < n; i++) {
        uint8_t want[32];
        if (seals[i].index != i) return CS_ERR_TAMPER;
        next_seal(i, seals[i - 1].seal, seals[i].witness_digest, want);
        if (!cs_ct_equal(want, seals[i].seal, 32)) return CS_ERR_TAMPER;
    }
    return CS_OK;
}

static cs_status push(worm_ledger *l, const worm_seal *s)
{
    if (l->count == l->cap) {
        size_t ncap = l->cap ? l->cap * 2 : 16;
        worm_seal *p = realloc(l->seals, ncap * sizeof *p);
        if (!p) return CS_ERR_NOMEM;
        l->seals = p;
        l->cap = ncap;
    }
    l->seals[l->count++] = *s;
    return CS_OK;
}

static cs_status write_line(int fd, const worm_seal *s)
{
    char line[8 + 20 + 64 + 64 + 8], wh[65], sh[65];
    cs_hex(s->witness_digest, 32, wh);
    cs_hex(s->seal, 32, sh);
    int n = snprintf(line, sizeof line, "%llu %s %s\n", (unsigned long long)s->index, wh, sh);
    if (n <= 0 || (size_t)n >= sizeof line) return CS_ERR_IO;
    ssize_t w = write(fd, line, (size_t)n);          /* O_APPEND: one atomic append per seal */
    if (w != n) return CS_ERR_IO;
    return fsync(fd) == 0 ? CS_OK : CS_ERR_IO;
}

static cs_status load_file(worm_ledger *l, const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f) return errno == ENOENT ? CS_OK : CS_ERR_IO;
    char line[256];
    cs_status st = CS_OK;
    while (fgets(line, sizeof line, f)) {
        size_t len = strlen(line);
        if (len == 0 || line[len - 1] != '\n') { st = CS_ERR_TAMPER; break; }   /* truncated line */
        line[len - 1] = '\0';
        unsigned long long idx;
        char wh[65], sh[65], extra;
        if (sscanf(line, "%llu %64s %64s %c", &idx, wh, sh, &extra) != 3) { st = CS_ERR_TAMPER; break; }
        worm_seal s;
        memset(&s, 0, sizeof s);
        s.index = idx;
        if (cs_unhex(wh, s.witness_digest, 32) != 0 || cs_unhex(sh, s.seal, 32) != 0) { st = CS_ERR_TAMPER; break; }
        st = push(l, &s);
        if (st != CS_OK) break;
    }
    if (st == CS_OK && ferror(f)) st = CS_ERR_IO;
    fclose(f);
    if (st == CS_OK && l->count > 0) st = worm_verify_chain(l->seals, l->count);
    return st;
}

cs_status worm_open(worm_ledger *l, const char *path)
{
    if (!l) return CS_ERR_ARG;
    memset(l, 0, sizeof *l);
    l->fd = -1;
    cs_status st = CS_OK;
    if (path) {
        st = load_file(l, path);
        if (st != CS_OK) { worm_close(l); return st; }
        l->fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0644);
        if (l->fd < 0) { worm_close(l); return CS_ERR_IO; }
    }
    if (l->count == 0) {
        worm_seal g;
        memset(&g, 0, sizeof g);
        genesis(g.seal);
        st = push(l, &g);
        if (st == CS_OK && l->fd >= 0) st = write_line(l->fd, &g);
        if (st != CS_OK) { worm_close(l); return st; }
    }
    return CS_OK;
}

cs_status worm_append(worm_ledger *l, const uint8_t witness_digest[32], worm_seal *out)
{
    if (!l || !witness_digest || l->count == 0) return CS_ERR_ARG;
    worm_seal s;
    memset(&s, 0, sizeof s);
    s.index = l->count;
    memcpy(s.witness_digest, witness_digest, 32);
    next_seal(s.index, l->seals[l->count - 1].seal, witness_digest, s.seal);
    if (l->fd >= 0) {
        cs_status st = write_line(l->fd, &s);        /* persist before acknowledging */
        if (st != CS_OK) return st;
    }
    cs_status st = push(l, &s);
    if (st != CS_OK) return st;
    if (out) *out = s;
    return CS_OK;
}

void worm_close(worm_ledger *l)
{
    if (!l) return;
    if (l->fd >= 0) close(l->fd);
    free(l->seals);
    memset(l, 0, sizeof *l);
    l->fd = -1;
}

size_t worm_count(const worm_ledger *l) { return l ? l->count : 0; }
const worm_seal *worm_at(const worm_ledger *l, size_t i) { return (l && i < l->count) ? &l->seals[i] : NULL; }
const worm_seal *worm_head(const worm_ledger *l) { return (l && l->count) ? &l->seals[l->count - 1] : NULL; }

cs_status worm_verify(const worm_ledger *l)
{
    if (!l) return CS_ERR_ARG;
    return worm_verify_chain(l->seals, l->count);
}
