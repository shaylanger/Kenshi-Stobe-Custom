/* snap_alloc.h -- gpugen CPU TU: tracked heap blocks (malloc/calloc/realloc/free of the adapter TU), so the state
 * snapshot (snap_cpu.c) can carry heap blocks and relocate pointers into them. Included first in cpu.c. */
#include <stddef.h>
static void *al_malloc(size_t n); static void *al_calloc(size_t a, size_t b); static void *al_realloc(void *p, size_t n);
static void al_free(void *p);
