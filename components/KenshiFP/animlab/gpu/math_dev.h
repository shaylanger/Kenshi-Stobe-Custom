/* math_dev.h -- libm for the device TU. fabsf/fminf/fmaxf/sqrtf/sqrt are exact (IEEE) on both sides. The
 * transcendental float functions come from glibc_dev.h (ports of glibc 2.36 sysdeps/ieee754/flt-32, the CPU replay's
 * libm, so the GPU gets the same bits) when AL_EXACT_LIBM is defined, else from libdevice (<= 2 ulp off glibc). */
float __nv_sinf(float); float __nv_cosf(float); float __nv_acosf(float); float __nv_asinf(float); float __nv_atan2f(float, float);
float __nv_expf(float); double __nv_log(double); float __nv_sqrtf(float); double __nv_sqrt(double);
static float fabsf(float x) { return __builtin_fabsf(x); }
static float fminf(float a, float b) { return a != a ? b : b != b ? a : a < b ? a : b; }   /* glibc: NaN-ignoring */
static float fmaxf(float a, float b) { return a != a ? b : b != b ? a : a > b ? a : b; }
static float sqrtf(float x) { return __nv_sqrtf(x); }
static float floorf(float x) { return __builtin_floorf(x); }   /* exact on both sides */
static float ceilf(float x) { return __builtin_ceilf(x); }
static float truncf(float x) { return __builtin_truncf(x); }
static double sqrt(double x) { return __nv_sqrt(x); }
static double log(double x) { return __nv_log(x); }
#ifdef AL_EXACT_LIBM
#include "glibc_dev.h"
#else
static float sinf(float x) { return __nv_sinf(x); }
static float cosf(float x) { return __nv_cosf(x); }
static float acosf(float x) { return __nv_acosf(x); }
static float asinf(float x) { return __nv_asinf(x); }
static float atan2f(float y, float x) { return __nv_atan2f(y, x); }
static float expf(float x) { return __nv_expf(x); }
#endif
