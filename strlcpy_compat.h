
/* ── strlcpy compat shim (glibc < 2.38) ────────────────────────────── */
#ifndef __STRLCPY_COMPAT_DEFINED
#define __STRLCPY_COMPAT_DEFINED
#include <stddef.h>
static __inline__ __attribute__((__unused__)) size_t
strlcpy(char *__restrict __dst, const char *__restrict __src, size_t __dstsize)
{
    size_t __srclen = strlen(__src);
    if (__dstsize > 0) {
        size_t __cplen = __srclen < __dstsize - 1 ? __srclen : __dstsize - 1;
        __builtin_memcpy(__dst, __src, __cplen);
        __dst[__cplen] = '\0';
    }
    return __srclen;
}
#endif /* __STRLCPY_COMPAT_DEFINED */
