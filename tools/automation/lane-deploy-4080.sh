#!/bin/bash
# lane-deploy-4080.sh - ship the imm26 server bundle to the 4080 and deploy it to a 4080 lane's private backend.
# Run from the 5090 in Git Bash or WSL (needs `ssh 4080`, key login). Never touches the live tree or a lane unless you say `run`.
#
#   lane-deploy-4080.sh push                       pack compose on the 5090 -> scp -> unpack on the 4080 (harmless; lanes untouched)
#   lane-deploy-4080.sh run <4080-lane-root> [--dry] [-v] [--migrate] [--no-push]
#                                                  push (unless --no-push) then run lane-deploy.sh on the 4080 against that lane
#   lane-deploy-4080.sh status                     print remote BUNDLE_ID vs a fresh local pack id (stale check)
# 4080 lane roots: /tmp/stobe-standalone4080-i4 (4080-i4), /tmp/stobe-standalone4080 (4080-i3). Run only BETWEEN ROWS.
# 4080-local alternative (after a push): ssh 4080 "wsl.exe -d DwemerAI4Skyrim3 -u root bash /mnt/c/KenshiTestRuns/imm26-install/bundle/lane-deploy.sh <root>"
# NOTE: the remote command line goes through cmd.exe: no & | < > in it.
set -o pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
TOOLS_WIN='C:\KenshiModding\tools\automation'
WSLD="DwemerAI4Skyrim3"
INST_WSL=/mnt/c/KenshiTestRuns/imm26-install
INST_GIT=/c/KenshiTestRuns/imm26-install
cmd=${1:-}; [ $# -gt 0 ] && shift
rwsl() { ssh -o ConnectTimeout=15 4080 "wsl.exe -d $WSLD -u root bash -c '$1'"; }   # $1 must contain no & | < >
lwsl() { # local: wsl.exe from Git Bash/Windows, or plain bash when already inside WSL
  if command -v wsl.exe >/dev/null 2>&1; then wsl.exe -d $WSLD -u root bash -c "$1"; else bash -c "$1"; fi
}

do_push() {
  local out id rid
  out=$(lwsl "bash /mnt/c/KenshiModding/tools/automation/lane-deploy.sh --pack $INST_WSL/bundle") || { echo "$out"; echo "lane-deploy-4080: pack failed"; return 1; }
  echo "$out"
  id=$(cat $INST_GIT/bundle/BUNDLE_ID)
  lwsl "cd $INST_WSL; rm -f bundle.tgz; tar czf bundle.tgz bundle" || return 1
  scp -q $INST_GIT/bundle.tgz "4080:C:/KenshiTestRuns/imm26-install/bundle.tgz" || { echo "lane-deploy-4080: scp failed"; return 1; }
  rid=$(rwsl "set -e; cd $INST_WSL; rm -rf bundle; tar xzf bundle.tgz; cat bundle/BUNDLE_ID" | tr -d '\r' | tail -1)
  if [ "$rid" = "$id" ]; then echo "lane-deploy-4080 PUSH ok bundle=$id on 4080:$INST_WSL/bundle"; else echo "lane-deploy-4080 PUSH FAILED local=$id remote=$rid"; return 1; fi
}

case "$cmd" in
  push) do_push;;
  status)
    lid=$(lwsl "bash /mnt/c/KenshiModding/tools/automation/lane-deploy.sh --pack /tmp/lanebundle-check-bundle >/dev/null; cat /tmp/lanebundle-check-bundle/BUNDLE_ID; rm -rf /tmp/lanebundle-check-bundle" | tr -d '\r' | tail -1)
    rid=$(rwsl "cat $INST_WSL/bundle/BUNDLE_ID" | tr -d '\r' | tail -1)
    [ "$lid" = "$rid" ] && echo "lane-deploy-4080 status: 4080 bundle current ($rid)" || echo "lane-deploy-4080 status: STALE local=$lid remote=$rid (run push)";;
  run)
    root=${1:-}; [ -n "$root" ] || { echo "usage: lane-deploy-4080.sh run <root> [--dry] [-v] [--migrate] [--no-push]"; exit 2; }
    shift; push=1; args=""
    for a in "$@"; do case "$a" in --no-push) push=0;; --dry|-v|--migrate) args="$args $a";; *) echo "unknown arg $a"; exit 2;; esac; done
    case "$root" in /tmp/stobe-*) ;; *) echo "refuse root $root"; exit 2;; esac
    case "$root" in *[!A-Za-z0-9_./-]*) echo "refuse root characters"; exit 2;; esac
    [ $push = 1 ] && { do_push || exit 1; }
    rwsl "bash $INST_WSL/bundle/lane-deploy.sh $root$args" | tr -d '\r'; exit ${PIPESTATUS[0]};;
  *) sed -n '2,12p' "$0"; exit 2;;
esac
