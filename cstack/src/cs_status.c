#include "cs_status.h"

const char *cs_status_str(cs_status s)
{
    switch (s) {
    case CS_OK:                 return "ok";
    case CS_ERR_ARG:            return "invalid argument";
    case CS_ERR_NOMEM:          return "out of memory";
    case CS_ERR_RANGE:          return "out of range";
    case CS_ERR_STATE:          return "invalid state";
    case CS_ERR_BOOT:           return "boot failure";
    case CS_ERR_ENTROPY:        return "entropy failure";
    case CS_ERR_MEMTEST:        return "memory verification failed";
    case CS_ERR_SINGULAR:       return "singular";
    case CS_ERR_UNPROVEN:       return "unproven claim";
    case CS_ERR_LIMIT:          return "resource limit exceeded";
    case CS_ERR_DRIFT:          return "drift detected";
    case CS_ERR_CONTRADICTION:  return "contradiction";
    case CS_ERR_TRAPPED:        return "trapped";
    case CS_ERR_DENIED:         return "denied";
    case CS_ERR_REPLAY:         return "replay";
    case CS_ERR_TAMPER:         return "tamper detected";
    case CS_ERR_IO:             return "i/o error";
    case CS_ERR_WORK:           return "work failed";
    }
    return "unknown";
}
