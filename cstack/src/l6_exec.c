#include "l6_exec.h"

#include <string.h>

void exec_init(exec_rt *rt)
{
    rt->last_seq = 0;
    rt->executed = 0;
}

cs_status exec_run(exec_rt *rt, const gateway *g, const gw_request *req, const gw_approval *appr,
                   exec_work_fn work, void *work_ctx, const sigma_limits *limits,
                   sigma_clock_fn clock, void *clock_ctx, exec_result *out)
{
    if (!rt || !g || !req || !appr || !work || !limits || !out) return CS_ERR_ARG;

    cs_status s = gw_verify_approval(g, req, appr);
    if (s != CS_OK) return CS_ERR_DENIED;
    if (appr->seq <= rt->last_seq) return CS_ERR_REPLAY;
    rt->last_seq = appr->seq;                       /* consumed from here on */
    rt->executed++;

    memset(out, 0, sizeof *out);
    sigma_ctx sg;
    sigma_init(&sg, limits, clock, clock_ctx);

    cs_status ws = sigma_charge_steps(&sg, 1);      /* dispatch cost */
    if (ws == CS_OK) ws = work(work_ctx, &sg, out->result_digest);
    if (ws == CS_OK) ws = sigma_check_time(&sg);
    if (sigma_status(&sg) != CS_OK) ws = sigma_status(&sg);   /* a breach wins over the work's own status */

    if (ws != CS_OK) memset(out->result_digest, 0, sizeof out->result_digest);
    out->status = ws;
    out->steps = sg.steps;
    out->mem_peak = sg.mem_peak;
    out->elapsed_ns = sigma_elapsed_ns(&sg);
    return ws;
}
