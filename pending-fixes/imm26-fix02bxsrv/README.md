# imm26-fix02bxsrv (row 02-bx principle_voiced_log)
Server PHP lib/imm26_c1_principles.php: new helper stobeImm26PrincipleSentenceVoices + slavery-only topic key `voice_extra`
(captive/prisoner/hostage/chain/rope/bind/cage/haul|sell|trade|buy|own ... people). A sentence counts as voiced when it has a stance phrase AND
(a profile word, as before) OR (a voice_extra word after the stance in the same clause, <= 90 chars, no sentence stop, stance not "I don't mind/care/know/see/think/have/need/want").
Run: `python3 apply.py <tree-root> [--check]` (idempotent, *.bak-fix02bxsrv) then `python3 apply_test.py <tree-root>`.
Trees patched: /root/imm26/compose, /tmp/stobe-imm26-5090/site, -5090-i5, -sfo-manual. NOT patched: /tmp/stobe-imm26-5090-i4/site (frozen for the ab2 pilot; run apply.py on it after the pilot).
Smoke/standalone sites have no imm26_c1_principles.php (older trees): skipped.
Not covered: bare fragments with no "I" ("Won't take captives, won't sell them.") still do not match the stance regex (unchanged).
