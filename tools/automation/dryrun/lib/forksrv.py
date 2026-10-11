#!/usr/bin/env python3
"""forksrv.py -- fork server for the dry-run fake game (speed-scout 2026-10-11).

A dry-run row sends ~3000 `stobe-auto` calls (fp-manual-hits-rows R08: 2905); each one started python and imported
kahstub/json/re (~20 ms of ~40 ms CPU per call; 4080 list starts waited 60-200 s on inline dry runs, ~20 min/day).
row.sh starts this server inside the sandbox (same chroot, pid namespace and env) with kahstub preloaded; the C client
lib/forkcli.c (the /dryrun/bin/stobe-auto wrapper) connects to $DR_STATE/fork.sock and passes its stdin/stdout/stderr
(SCM_RIGHTS), cwd, argv and environment. The server forks one child per call (copy-on-write, kahstub already imported):
the child takes over the client's fds, cwd and env, runs kahstub.py as __main__ (exactly the script the wrapper used to
exec) and sends back its exit status. The client stays alive (blocked on the socket) for the whole call, so `$!`, kill,
wait and timeout on it behave like before: a closed client connection kills the child (watcher thread).
Protocol: request = 4-byte length + NUL-separated fields: script, cwd, argc, argv..., then env "K=V" entries (rest);
reply = 4 bytes: exit status (signed int, little endian). Any failure on the client side = it execs python directly.
Usage: forksrv.py <socket path> <script to preload>...   (prints READY on stdout once listening)
"""
import array, os, runpy, signal, socket, struct, sys, threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


CODE = {}   # script path -> (mtime_ns, code object) of the preloaded scripts


def recv_request(c):
    fds = array.array('i')
    msg, anc, _f, _a = c.recvmsg(4, socket.CMSG_LEN(3 * fds.itemsize))
    for lvl, typ, data in anc:
        if lvl == socket.SOL_SOCKET and typ == socket.SCM_RIGHTS:
            fds.frombytes(data[:len(data) - (len(data) % fds.itemsize)])
    if len(msg) < 4 or len(fds) != 3:
        return None, None
    n = struct.unpack('<I', msg)[0]
    buf = b''
    while len(buf) < n:
        b = c.recv(n - len(buf))
        if not b:
            return None, None
        buf += b
    return buf.split(b'\0'), list(fds)


def child(c, f, fds):
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    for i, fd in enumerate(fds):
        os.dup2(fd, i)
        os.close(fd)
    script, cwd, argc = f[0].decode(), f[1].decode(), int(f[2])
    argv = [x.decode('utf-8', 'surrogateescape') for x in f[3:3 + argc]]
    env = [x.decode('utf-8', 'surrogateescape') for x in f[3 + argc:] if x]
    os.environ.clear()
    for kv in env:
        k, _, v = kv.partition('=')
        os.environ[k] = v
    try:
        os.chdir(cwd)
    except OSError:
        pass
    sys.stdin = open(0, 'r', closefd=False)
    sys.stdout = open(1, 'w', closefd=False)
    sys.stderr = open(2, 'w', closefd=False)
    sys.argv = [script] + argv

    def watch():   # the client went away (killed, timeout): end this call like a killed python would
        try:
            while True:
                if c.recv(1) == b'':
                    os._exit(143)
        except OSError:
            os._exit(143)
    threading.Thread(target=watch, daemon=True).start()
    code = 0
    try:
        cc = CODE.get(script)
        if cc and cc[0] == os.stat(script).st_mtime_ns:   # precompiled by the server (compiling kahstub.py = ~20 ms)
            exec(cc[1], {'__name__': '__main__', '__file__': script, '__builtins__': __builtins__})
        else:
            runpy.run_path(script, run_name='__main__')
    except SystemExit as e:
        if e.code is None:
            code = 0
        elif isinstance(e.code, int):
            code = e.code
        else:
            sys.stderr.write('%s\n' % e.code)
            code = 1
    except BaseException:   # noqa: B902 - same as an uncaught exception in python: traceback, status 1
        import traceback
        traceback.print_exc()
        code = 1
    for s in (sys.stdout, sys.stderr):
        try:
            s.flush()
        except (OSError, ValueError):
            pass
    try:
        c.sendall(struct.pack('<i', code))
    except OSError:
        pass
    os._exit(code & 0xff)


def main():
    path, pre = sys.argv[1], sys.argv[2:]
    for p in pre:   # import the modules the scripts import (kahstub, dr, kfpreply ...), not their __main__
        d, b = os.path.split(os.path.abspath(p))
        if d not in sys.path:
            sys.path.insert(0, d)
        __import__(os.path.splitext(b)[0])
        with open(p, 'rb') as fh:
            CODE[os.path.abspath(p)] = (os.stat(p).st_mtime_ns, compile(fh.read(), os.path.abspath(p), 'exec'))
    try:
        os.unlink(path)
    except OSError:
        pass
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    s.listen(64)
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)   # children reap themselves
    print('READY', flush=True)
    sys.stdout.flush()
    sys.stderr.flush()
    while True:
        try:
            c, _ = s.accept()
        except InterruptedError:
            continue
        try:
            f, fds = recv_request(c)
        except OSError:
            f, fds = None, None
        if f is None:
            c.close()
            for fd in fds or []:
                os.close(fd)
            continue
        pid = os.fork()
        if pid == 0:
            s.close()
            try:
                child(c, f, fds)
            finally:
                os._exit(1)
        c.close()
        for fd in fds:
            os.close(fd)


if __name__ == '__main__':
    main()
