# imm26-fix02bxregex (row 02-bx rep1 principle_voiced_log 2<3)
Server PHP lib/imm26_c1_principles.php, on top of fix02bxsrv (must be applied first; apply.py asserts it).
1. stanceSay += "(that|it|this)('s| is) not (a thing|something|what) I do|would|will|could", "I do not", "I'm/I am not going to|doing".
2. slavery voice_extra += manacles/fetters/handcuffs/leg-irons, and "irons" only after put/clap/snap/lock/slap (so "irons in the fire" does not match).
Unchanged: stance-before-word clause rule, "I don't mind/care/..." exclusion, profile path, topic scope.
Run: `python3 apply.py <tree-root> [--check]` then `python3 apply_test.py <tree-root>` (idempotent, *.bak-fix02bxregex).
Tested on a copy of /root/imm26/compose: 6 new positives FAIL unpatched; patched = 85 pass / 0 fail (73 + 12 new); php -l clean. Not applied to any live site/tree.
