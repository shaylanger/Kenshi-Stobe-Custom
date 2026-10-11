/* forkcli.c -- client of lib/forksrv.py (speed-scout 2026-10-11): `forkcli <script> [args...]` runs <script> through the
 * dry-run fork server ($DR_STATE/fork.sock) instead of starting python: passes stdin/stdout/stderr (SCM_RIGHTS), cwd, argv
 * and environment, waits for the exit status. Stays alive for the whole call (kill/timeout/wait on it work as before;
 * the server child dies when this process does). No server / any error before the request is sent = exec python3. */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

extern char **environ;

static void fallback(int argc, char **argv) {
  char **a = calloc(argc + 2, sizeof *a);
  a[0] = "/usr/bin/python3";
  for (int i = 1; i < argc; i++) a[i] = argv[i];
  execv(a[0], a);
  perror("forkcli: exec python3");
  _exit(127);
}

static int put(char **b, size_t *n, size_t *cap, const char *s) {
  size_t l = strlen(s) + 1;
  if (*n + l > *cap) { *cap = (*n + l) * 2; char *nb = realloc(*b, *cap); if (!nb) return -1; *b = nb; }
  memcpy(*b + *n, s, l); *n += l; return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: forkcli <script> [args]\n"); return 2; }
  const char *st = getenv("DR_STATE");
  if (!st || getenv("DR_NOFORK")) fallback(argc, argv);
  struct sockaddr_un sa; memset(&sa, 0, sizeof sa); sa.sun_family = AF_UNIX;
  if (snprintf(sa.sun_path, sizeof sa.sun_path, "%s/fork.sock", st) >= (int)sizeof sa.sun_path) fallback(argc, argv);
  int s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (s < 0 || connect(s, (struct sockaddr *)&sa, sizeof sa) < 0) fallback(argc, argv);
  char cwd[4096]; if (!getcwd(cwd, sizeof cwd)) strcpy(cwd, "/");
  char *b = NULL; size_t n = 0, cap = 0; char num[16];
  snprintf(num, sizeof num, "%d", argc - 2);
  int bad = put(&b, &n, &cap, argv[1]) || put(&b, &n, &cap, cwd) || put(&b, &n, &cap, num);
  for (int i = 2; i < argc && !bad; i++) bad = put(&b, &n, &cap, argv[i]);
  for (char **e = environ; *e && !bad; e++) bad = put(&b, &n, &cap, *e);
  if (bad) fallback(argc, argv);
  uint32_t len = (uint32_t)n;   /* little endian host (x86_64) */
  int fds[3] = {0, 1, 2};
  char cbuf[CMSG_SPACE(sizeof fds)]; memset(cbuf, 0, sizeof cbuf);
  struct iovec io = {&len, 4};
  struct msghdr m; memset(&m, 0, sizeof m);
  m.msg_iov = &io; m.msg_iovlen = 1; m.msg_control = cbuf; m.msg_controllen = sizeof cbuf;
  struct cmsghdr *c = CMSG_FIRSTHDR(&m);
  c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS; c->cmsg_len = CMSG_LEN(sizeof fds);
  memcpy(CMSG_DATA(c), fds, sizeof fds);
  if (sendmsg(s, &m, MSG_NOSIGNAL) != 4) fallback(argc, argv);
  for (size_t o = 0; o < n;) {   /* request sent from here on: no fallback (the call may already run) */
    ssize_t w = send(s, b + o, n - o, MSG_NOSIGNAL);
    if (w <= 0) { if (errno == EINTR) continue; fprintf(stderr, "forkcli: send failed\n"); return 1; }
    o += (size_t)w;
  }
  int32_t code; size_t got = 0;
  while (got < 4) {
    ssize_t r = recv(s, (char *)&code + got, 4 - got, 0);
    if (r == 0) { fprintf(stderr, "forkcli: server child died\n"); return 1; }
    if (r < 0) { if (errno == EINTR) continue; return 1; }
    got += (size_t)r;
  }
  return code & 0xff;
}
