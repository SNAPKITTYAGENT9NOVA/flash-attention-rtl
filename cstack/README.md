# C stack

A layered, deterministic core in C11. Ten layers; each depends only on the ones below it, and a job passes through all of them in order. The first layer that refuses stops the job and nothing below it runs.

```
L0 Boot              CPU detection · entropy source · memory verify
L1 UAC               Goldilocks F_p · PMat matrices · tensors
L2 ALP boundary      proof availability · sorry manifest
L3 Sigma kernel      resource limits · drift detection
L4 Dissonance        contradiction detection · violation trapping
L5 Triple-lock       Guardian → Examiner → Publisher
L6 Execution         approved work only
L7 Unified witness   cryptographic evidence
L8 WORM ledger       seal_0 → seal_1 → … → seal_n
L9 Observability     metrics · audit
```

## Build and test

```bash
cd cstack
make test     # build everything with -Wall -Wextra -Wpedantic -Wconversion -Werror and run all tests
make san      # the same tests under AddressSanitizer + UndefinedBehaviorSanitizer
make demo     # walk jobs through the stack
```

Needs a C11 compiler and Linux (`getrandom`). Developed and tested on x86-64 with gcc and clang; CPU feature detection is x86-only (other architectures report just the architecture name).

## Layers

| Layer | Files | What it does |
|-------|-------|--------------|
| 0 Boot | `l0_boot` | CPU vendor and features via `cpuid`; OS entropy with a health test (rejects constant streams and runs of 4 identical bytes); walking-pattern memory test; `boot_id = SHA-256(seed ‖ cpu)` |
| 1 UAC | `l1_goldilocks`, `l1_pmat`, `l1_tensor` | Arithmetic mod p = 2⁶⁴ − 2³² + 1 with a fast reduction; dense matrices (add, mul, transpose, determinant, Gauss-Jordan inverse); rank ≤ 4 tensors (Hadamard, outer product, axis contraction) |
| 2 ALP boundary | `l2_alp` | Registry of claims with attached Lean-style proof sources. A source is `proven` only if it has no `sorry` (comments and strings are skipped); the manifest lists every claim with its state and SHA-256, plus the total sorry count |
| 3 Sigma kernel | `l3_sigma` | Per-job memory, step and wall-time limits with overflow-safe accounting and a latched breach; integer EWMA drift detector; state-digest drift check |
| 4 Dissonance | `l4_dissonance` | Named facts with implication and exclusion rules, propagated by modus ponens and modus tollens; assertions apply atomically or not at all; invariants; a trap that refuses everything until an operator reset |
| 5 Triple-lock | `l5_gateway` | Three stages with separate keys derived from the boot seed. Each stage accepts only a token minted by the previous one, so the order cannot be skipped; only the Publisher issues an approval (HMAC over request digest and a strictly increasing sequence number) |
| 6 Execution | `l6_exec` | The only way to run work. Verifies the approval for exactly this request, consumes it (single use, in order), runs the work under Sigma limits |
| 7 Unified witness | `l7_witness` | One record per execution binding boot id, request, approval, result digest, steps and peak memory; SHA-256 digest over a canonical serialization, HMAC signature |
| 8 WORM ledger | `l8_worm` | `seal_i = SHA-256(i ‖ seal_{i-1} ‖ witness_i)`. No API to modify or delete an entry. File-backed ledgers are opened `O_APPEND` and fully re-verified on open |
| 9 Observability | `l9_obs` | Counters, gauges and summaries with text export; ring-buffer audit log whose events are hash-chained |

`cstack.c` wires the layers together (`cstack_init`, `cstack_submit`, `cstack_verify`). Beyond the individual layers it adds three cross-layer checks: the policy and limits are hashed at init and re-checked on every job (in-memory tampering is reported as drift), the Dissonance invariants watch the ledger chain, the audit chain, and that no approval was consumed that was never issued, and a steps-per-job drift detector can trap the stack.

## Using it

```c
#include "cstack.h"

cstack cs;
cstack_config cfg = {0};
cfg.policy.allowed_kinds = 1u << 1;
cfg.policy.max_payload   = 256;
cfg.limits = (sigma_limits){ .max_mem_bytes = 1 << 20, .max_steps = 1000000, .max_ns = 5000000000ull };
cstack_init(&cs, &cfg);

alp_attach_proof(&cs.alp, "my_claim", lean_source, lean_len);

cstack_job job = { .id = 1, .kind = 1, .payload = "...", .payload_len = 3,
                   .requires = (const char *[]){"my_claim"}, .nrequires = 1,
                   .work = my_work, .work_ctx = &ctx };
cstack_result r;
cs_status s = cstack_submit(&cs, &job, &r);   /* r.failed_layer tells you where it stopped */
```

`my_work` has the signature `cs_status (*)(void *ctx, sigma_ctx *sigma, uint8_t result_digest[32])`: it charges memory and steps to `sigma` and returns a digest of its result.

## Behaviour worth knowing

- Everything except the boot entropy and wall-clock timestamps is deterministic: the same entropy and the same jobs give the same ledger head (witnesses contain no timestamps).
- Work that fails or hits a limit after being approved is still witnessed and sealed, with its status recorded.
- Approvals must be consumed in the order they were issued.
- A file ledger detects edits, deletions, reordering and partial lines. Truncating whole trailing lines yields a shorter valid chain, so pair the ledger with an externally stored head if that matters.
- Single-threaded. Pointers from `worm_at` / `worm_head` are valid until the next append.
- The ALP layer scans proof sources for `sorry`; it does not run a proof checker.
