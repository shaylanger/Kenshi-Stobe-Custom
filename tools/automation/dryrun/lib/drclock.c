/* drclock.c -- fast `sleep` and `date` for the take dry run (tools/automation/dryrun; built by dryrun.sh into
 * /root/.cache/kah-dryrun/drclock, installed in the sandbox as /dryrun/bin/sleep and /dryrun/bin/date).
 * Same virtual clock protocol as lib/dr.py (vnow, advance_to, vwait): $DR_STATE/clock = offset s, $DR_STATE/lock =
 * flock, $DR_STATE/sleepers/<pid>.<n> = wake time. A C binary instead of a python start per call: take scripts poll with
 * `sleep 0.1`/`sleep 0.2` hundreds of times per row (rig-runner 2026-10-10: a weapon-sweep row took ~2 min real). */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static char ST[512], SD[600];

static double now_real(void) { struct timespec t; clock_gettime(CLOCK_REALTIME, &t); return t.tv_sec + t.tv_nsec / 1e9; }

static double offset(void) {
  char p[640], b[64] = {0}; snprintf(p, sizeof p, "%s/clock", ST);
  int fd = open(p, O_RDONLY); if (fd < 0) return 0;
  ssize_t n = read(fd, b, sizeof b - 1); close(fd); if (n <= 0) return 0;
  return atof(b);
}
static double vnow(void) { return now_real() + offset(); }

static void write_offset(double o) {   /* atomic, like dr._write_offset */
  char p[640], t[700]; snprintf(p, sizeof p, "%s/clock", ST); snprintf(t, sizeof t, "%s.%d", p, (int)getpid());
  FILE *f = fopen(t, "w"); if (!f) return; fprintf(f, "%.6f", o); fclose(f); rename(t, p);
}
static int lock_on(void) {   /* $DR_STATE/lock, the same flock as dr.Lock */
  char p[640]; snprintf(p, sizeof p, "%s/lock", ST);
  int fd = open(p, O_RDWR | O_CREAT | O_APPEND, 0644); if (fd >= 0) flock(fd, LOCK_EX); return fd;
}
static void lock_off(int fd) { if (fd >= 0) { flock(fd, LOCK_UN); close(fd); } }
static void advance_to_locked(double w) { double d = w - vnow(); if (d > 0) write_offset(offset() + d); }
static double clock_mtime(void) {
  char p[640]; struct stat s; snprintf(p, sizeof p, "%s/clock", ST);
  if (stat(p, &s)) return 0; return s.st_mtim.tv_sec + s.st_mtim.tv_nsec / 1e9;
}
static void nap(double s) { struct timespec t = { (time_t)s, (long)((s - (time_t)s) * 1e9) }; nanosleep(&t, 0); }

/* another process in the sandbox (own pid namespace) runnable or in disk wait: the foreground is between two waits */
static int busy(int samples) {
  int me = getpid();
  for (int i = 0; i < samples; i++) {
    DIR *d = opendir("/proc"); struct dirent *e; if (!d) return 0;
    while ((e = readdir(d))) {
      if (e->d_name[0] < '0' || e->d_name[0] > '9' || atoi(e->d_name) == me) continue;
      char p[300], b[1024]; snprintf(p, sizeof p, "/proc/%s/stat", e->d_name);
      int fd = open(p, O_RDONLY); if (fd < 0) continue;
      ssize_t n = read(fd, b, sizeof b - 1); close(fd); if (n <= 0) continue; b[n] = 0;
      char *r = strrchr(b, ')'); if (r && (r[2] == 'R' || r[2] == 'D')) { closedir(d); return 1; }
      /* blocked on the clock lock (a sleeper about to register / a harness call about to advance): not idle */
      snprintf(p, sizeof p, "/proc/%s/wchan", e->d_name); fd = open(p, O_RDONLY);
      if (fd >= 0) { n = read(fd, b, sizeof b - 1); close(fd); if (n > 0) { b[n] = 0; if (strstr(b, "lock")) { closedir(d); return 1; } } }
    }
    closedir(d); nap(0.002);
  }
  return 0;
}

/* earliest wake time of the live registered sleepers (dead ones removed); 1e300 = none */
static double min_wake(void) {
  double m = 1e300; DIR *d = opendir(SD); struct dirent *e; if (!d) return m;
  while ((e = readdir(d))) {
    if (e->d_name[0] == '.') continue;
    char p[1000], pp[64], b[64] = {0}; snprintf(p, sizeof p, "%s/%s", SD, e->d_name);
    snprintf(pp, sizeof pp, "/proc/%d", atoi(e->d_name));
    if (access(pp, F_OK)) { unlink(p); continue; }
    int fd = open(p, O_RDONLY); if (fd < 0) continue;
    ssize_t n = read(fd, b, sizeof b - 1); close(fd);
    double w = n > 0 ? atof(b) : 1e300; if (w < m) m = w;
  }
  closedir(d); return m;
}

static void vwait(double dur) {   /* dr.vwait: discrete-event wait, see dr.py */
  if (dur <= 0) return;
  const char *ie = getenv("DR_IDLE"); double idle = ie ? atof(ie) : 0.003;
  /* register under the clock lock: an advancer holds it from its busy check to the jump, so a sleeper is either
     registered before (seen by min_wake) or blocked on the lock (seen by busy) -- never missed (a C sleep starts and
     naps within the 2 ms between two busy samples) */
  int lk = lock_on();
  double wake = vnow() + dur; mkdir(SD, 0755);
  char me[1000]; snprintf(me, sizeof me, "%s/%d.%ld", SD, (int)getpid(), (long)(now_real() * 1e6) % 1000000);
  FILE *f = fopen(me, "w"); if (f) { fprintf(f, "%.6f", wake); fclose(f); }
  lock_off(lk);
  double last = clock_mtime(), t_idle = now_real();
  while (vnow() < wake) {
    nap(0.003);
    double m = clock_mtime();
    if (m != last) { last = m; t_idle = now_real(); continue; }
    if (now_real() - t_idle < idle) continue;
    if (wake > min_wake() + 1e-6) continue;   /* cheap pre-check without the lock */
    lk = lock_on();
    int go = wake <= min_wake() + 1e-6 && !busy(2) && clock_mtime() == last;
    if (go) advance_to_locked(wake);
    lock_off(lk);
    if (go) break;
  }
  unlink(me);
}

static double dur(const char *x) {
  char *e; double v = strtod(x, &e); if (e == x) return -1;
  switch (*e) { case 0: case 's': return v; case 'm': return v * 60; case 'h': return v * 3600; case 'd': return v * 86400; }
  return -1;
}

int main(int argc, char **argv) {
  const char *s = getenv("DR_STATE"); snprintf(ST, sizeof ST, "%s", s && *s ? s : "/tmp/dr-state");
  snprintf(SD, sizeof SD, "%s/sleepers", ST);
  const char *name = strrchr(argv[0], '/'); name = name ? name + 1 : argv[0];
  if (!strcmp(name, "date")) {
    for (int i = 1; i < argc; i++)
      if (!strncmp(argv[i], "-d", 2) || !strncmp(argv[i], "--date", 6) || !strncmp(argv[i], "-r", 2) ||
          !strncmp(argv[i], "--reference", 11) || !strncmp(argv[i], "-s", 2) || !strncmp(argv[i], "--set", 5)) {
        argv[0] = "date"; execv("/bin/date", argv); return 127; }
    char at[64]; snprintf(at, sizeof at, "@%.6f", vnow());
    char **a = calloc(argc + 3, sizeof *a); a[0] = "date"; a[1] = "-d"; a[2] = at;
    for (int i = 1; i < argc; i++) a[i + 2] = argv[i];
    execv("/bin/date", a); return 127;
  }
  /* sleep */
  double d = 0;
  for (int i = 1; i < argc; i++) { double v = dur(argv[i]); if (v < 0) { fprintf(stderr, "sleep: invalid time interval '%s'\n", argv[i]); return 1; } d += v; }
  if (argc < 2) { fprintf(stderr, "sleep: missing operand\n"); return 1; }
  double r0 = now_real(); vwait(d);
  if (getenv("DR_PROF")) { char p[640]; snprintf(p, sizeof p, "%s/prof", ST); FILE *f = fopen(p, "a");
    if (f) { fprintf(f, "sleep %.3f real %.4f\n", d, now_real() - r0); fclose(f); } }
  return 0;
}
