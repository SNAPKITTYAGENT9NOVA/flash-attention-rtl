#ifndef CS_STATUS_H
#define CS_STATUS_H

typedef enum cs_status {
    CS_OK = 0,
    CS_ERR_ARG,            /* invalid argument */
    CS_ERR_NOMEM,          /* allocation failed or size overflow */
    CS_ERR_RANGE,          /* index / dimension out of range */
    CS_ERR_STATE,          /* operation not valid in the current state */
    CS_ERR_BOOT,           /* layer 0 failure */
    CS_ERR_ENTROPY,        /* entropy source failed its health test */
    CS_ERR_MEMTEST,        /* memory verification failed */
    CS_ERR_SINGULAR,       /* matrix not invertible / division by zero */
    CS_ERR_UNPROVEN,       /* claim has no proof or its proof contains sorry */
    CS_ERR_LIMIT,          /* resource limit exceeded */
    CS_ERR_DRIFT,          /* drift detected */
    CS_ERR_CONTRADICTION,  /* contradiction detected */
    CS_ERR_TRAPPED,        /* dissonance engine is trapped */
    CS_ERR_DENIED,         /* gateway denied the request */
    CS_ERR_REPLAY,         /* approval already used or out of order */
    CS_ERR_TAMPER,         /* integrity check failed */
    CS_ERR_IO,
    CS_ERR_WORK            /* approved work reported failure */
} cs_status;

const char *cs_status_str(cs_status s);

#endif
