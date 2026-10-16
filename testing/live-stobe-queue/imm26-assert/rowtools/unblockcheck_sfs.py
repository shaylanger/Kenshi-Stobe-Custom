#!/usr/bin/env python3
"""unblockcheck_sfs.py <ROW> <evidence-dir>   verdict for 08-d v2 (imm26-sfS).  Runs the UNCHANGED unblockcheck_a.c_08d (-> rowcheck_trip.c_08d) on a VIEW of the evidence dir in which
bored_log.txt is replaced by bored_log_after1.txt (the SAY/BORED lines logged after tick 1, written by unblockdefs_sfs.sh rd_08d).  Reason: tick 1 is the trip ARRIVAL remark
("I'll be around Squin a while ..."), which contains the topic word, so `no_npc_ask_about_the_topic` (SAY lines matching fur|squin) must look only at the later ticks.  A follow-up ask
on tick 1 is still caught by no_situated_remark_claim_for_closed_topic (fu_after.txt claim rows).  Without bored_log_after1.txt (old evidence) the dir is checked as is.
The RESULT line names the real evidence dir.  Rows: 08-d only.  `unblockcheck_sfs.py --has <ROW>` exits 0 for 08-d (unblockpy_sfs.sh)."""
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import unblockcheck_a as ua  # noqa: E402

rc = ua.rc


def main(argv):
    if len(argv) == 3 and argv[1] == '--has':
        return 0 if rc.norm(argv[2]) == '08-d' else 1
    if len(argv) < 3 or rc.norm(argv[1]) != '08-d':
        print('usage: unblockcheck_sfs.py <ROW 08-d> <evidence-dir>', file=sys.stderr)
        return 2
    ev = argv[2]
    after = os.path.join(ev, 'bored_log_after1.txt')
    tmp = None
    view = ev
    try:
        if os.path.isfile(after):
            tmp = tempfile.mkdtemp(prefix='sfs-view-')
            view = os.path.join(tmp, 'ev')
            shutil.copytree(ev, view)
            shutil.copyfile(after, os.path.join(view, 'bored_log.txt'))
        v = ua.V(argv[1])
        ua.CHECKS['08-d'](v, view)
        if v.note:
            v.good.append(v.note)
        if tmp:
            v.good.append('R~ ask check on lines after tick 1 only (bored_log_after1.txt, mark %s)' % ' '.join((rc.rd(ev, 'bored_after1_mark.txt') or 'none').split()))
        return v.emit(ev)
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
