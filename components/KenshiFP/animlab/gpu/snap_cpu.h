/* snap_cpu.h -- gpugen CPU TU: tables of every mutable global and function (filled in by gpugen) */
typedef struct { const char *name; void *addr; unsigned long size; } AlGlobal;
typedef struct { const char *name; void *addr; } AlFunc;
