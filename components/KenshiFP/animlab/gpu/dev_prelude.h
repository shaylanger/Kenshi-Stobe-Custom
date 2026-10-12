/* dev_prelude.h -- device stand-ins for the system headers the adapter TU used (gpugen drops every system-header item;
 * clang --target=nvptx64-nvidia-cuda -fno-builtin, plain C). Types must have the x86-64 Linux sizes: every mutable
 * global is copied byte for byte between the CPU replay and the GPU state (kst_layout checks every size).
 * Only what the frame loop needs is real (string compares, memcpy/memset, %s/%d snprintf, libm); file I/O, logging and
 * the text parsers are host-only paths (load_rec, fp_vm replies, vm_rec_dump) and are stubs here. */
typedef unsigned long size_t;
typedef unsigned long uintptr_t;
typedef long ptrdiff_t;
typedef __builtin_va_list va_list;
typedef struct AlFile FILE;
typedef struct { long b[25]; } jmp_buf[1];   /* glibc x86-64: struct __jmp_buf_tag[1], 200 bytes */
#define stderr ((FILE *)0)
#define stdout ((FILE *)0)
#define NULL ((void *)0)

/* ---- libm: math_dev.h (exact ports where available, else libdevice) ---- */
#include "math_dev.h"

/* ---- string ---- */
static int strcmp(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return (unsigned char)*a - (unsigned char)*b; }
static int strncmp(const char *a, const char *b, size_t n) { for (; n; n--, a++, b++) { if (*a != *b) return (unsigned char)*a - (unsigned char)*b; if (!*a) return 0; } return 0; }
static size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
static char *strchr(const char *s, int c) { for (;; s++) { if (*s == (char)c) return (char *)s; if (!*s) return 0; } }
static char *strstr(const char *h, const char *n) { size_t k = strlen(n); for (; *h; h++) if (!strncmp(h, n, k)) return (char *)h; return k ? 0 : (char *)h; }
static int memcmp(const void *a, const void *b, size_t n) { const unsigned char *x = a, *y = b; for (; n; n--, x++, y++) if (*x != *y) return *x - *y; return 0; }
static void *memcpy(void *d, const void *s, size_t n) { unsigned char *x = d; const unsigned char *y = s; while (n--) *x++ = *y++; return d; }
static void *memset(void *d, int c, size_t n) { unsigned char *x = d; while (n--) *x++ = (unsigned char)c; return d; }
static char *strncpy(char *d, const char *s, size_t n) { size_t i = 0; for (; i < n && s[i]; i++) d[i] = s[i]; for (; i < n; i++) d[i] = 0; return d; }
static int abs(int x) { return x < 0 ? -x : x; }

/* ---- heap: CUDA device malloc ---- */
void *malloc(size_t n); void free(void *p);
static void *calloc(size_t a, size_t b) { void *p = malloc(a * b); if (p) memset(p, 0, a * b); return p; }
static void *realloc(void *p, size_t n) { (void)p; (void)n; return 0; }   /* host-only (load_rec) */

/* ---- formatting: %s %d %u %x %c %ld %lu and %.Nf (not glibc-exact rounding; only state strings use it on the device) ---- */
static int al_vsnprintf(char *b, size_t cap, const char *f, va_list ap)
{
    size_t k = 0;
#define AL_PUT(ch) do { if (k + 1 < cap) b[k] = (ch); k++; } while (0)
    for (; *f; f++) {
        if (*f != '%') { AL_PUT(*f); continue; }
        f++; int prec = -1, lng = 0, width = 0;
        while (*f == '-' || *f == '+' || *f == ' ' || *f == '0') f++;
        while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
        if (*f == '.') { f++; prec = 0; while (*f >= '0' && *f <= '9') prec = prec * 10 + (*f++ - '0'); }
        while (*f == 'l') { lng++; f++; }
        if (*f == 's') { const char *s = __builtin_va_arg(ap, const char *); if (!s) s = "(null)"; for (int i = 0; s[i] && (prec < 0 || i < prec); i++) AL_PUT(s[i]); }
        else if (*f == 'c') AL_PUT((char)__builtin_va_arg(ap, int));
        else if (*f == 'd' || *f == 'i' || *f == 'u' || *f == 'x' || *f == 'p') {
            unsigned long long v; int neg = 0, base = (*f == 'x' || *f == 'p') ? 16 : 10;
            if (*f == 'p') v = (unsigned long long)__builtin_va_arg(ap, void *);
            else if (*f == 'd' || *f == 'i') { long long s = lng ? __builtin_va_arg(ap, long) : __builtin_va_arg(ap, int); if (s < 0) { neg = 1; v = -(unsigned long long)s; } else v = s; }
            else v = lng ? __builtin_va_arg(ap, unsigned long) : __builtin_va_arg(ap, unsigned);
            char t[24]; int n = 0; do { t[n++] = "0123456789abcdef"[v % base]; v /= base; } while (v);
            if (neg) AL_PUT('-'); while (n) AL_PUT(t[--n]);
        }
        else if (*f == 'f' || *f == 'g') {
            double v = __builtin_va_arg(ap, double); if (prec < 0) prec = 6; if (v < 0) { AL_PUT('-'); v = -v; }
            double sc = 1; for (int i = 0; i < prec; i++) sc *= 10; unsigned long long q = (unsigned long long)(v * sc + 0.5);
            unsigned long long ip = q / (unsigned long long)sc, fp = q % (unsigned long long)sc;
            char t[24]; int n = 0; do { t[n++] = '0' + ip % 10; ip /= 10; } while (ip); while (n) AL_PUT(t[--n]);
            if (prec) { AL_PUT('.'); char u[24]; for (int i = prec - 1; i >= 0; i--) { u[i] = '0' + fp % 10; fp /= 10; } for (int i = 0; i < prec; i++) AL_PUT(u[i]); }
        }
        else if (*f == '%') AL_PUT('%');
        else if (!*f) break;
        (void)width;
    }
    if (cap) b[k < cap ? k : cap - 1] = 0;
#undef AL_PUT
    return (int)k;
}
static int snprintf(char *b, size_t cap, const char *f, ...) { va_list ap; __builtin_va_start(ap, f); int n = al_vsnprintf(b, cap, f, ap); __builtin_va_end(ap); return n; }

/* ---- host-only paths: stubs ---- */
static int printf(const char *f, ...) { (void)f; return 0; }
static int fprintf(FILE *o, const char *f, ...) { (void)o; (void)f; return 0; }
static int vfprintf(FILE *o, const char *f, va_list ap) { (void)o; (void)f; (void)ap; return 0; }
static int fputc(int c, FILE *o) { (void)o; return c; }
static int fputs(const char *s, FILE *o) { (void)s; (void)o; return 0; }
static FILE *fopen(const char *p, const char *m) { (void)p; (void)m; return 0; }
static int fclose(FILE *f) { (void)f; return 0; }
static char *fgets(char *s, int n, FILE *f) { (void)s; (void)n; (void)f; return 0; }
static int sscanf(const char *s, const char *f, ...) { (void)s; (void)f; return 0; }
static long strtol(const char *s, char **e, int base) { long v = 0; int neg = 0; (void)base; while (*s == ' ') s++; if (*s == '-') { neg = 1; s++; } while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0'); if (e) *e = (char *)s; return neg ? -v : v; }
static int atoi(const char *s) { return (int)strtol(s, 0, 10); }
static float strtof(const char *s, char **e) { (void)s; if (e) *e = (char *)s; return 0.0f; }   /* host-only (fp_vm set parser) */
static double atof(const char *s) { (void)s; return 0.0; }
static char *strtok(char *s, const char *d) { (void)s; (void)d; return 0; }
static char *strtok_r(char *s, const char *d, char **sv) { (void)s; (void)d; (void)sv; return 0; }
static void qsort(void *b, size_t n, size_t w, int (*c)(const void *, const void *))
{   /* insertion sort (host-only path: calibrate) */
    unsigned char *a = b, t[64];
    for (size_t i = 1; i < n; i++) for (size_t j = i; j > 0 && c(a + (j - 1) * w, a + j * w) > 0; j--) {
        memcpy(t, a + j * w, w); memcpy(a + j * w, a + (j - 1) * w, w); memcpy(a + (j - 1) * w, t, w); }
}
#define _setjmp(jb) 0   /* the plugin's crash guard: no faults to catch on the device */
