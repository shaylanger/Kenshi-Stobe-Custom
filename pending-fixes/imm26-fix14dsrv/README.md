# imm26-fix14dsrv (14-d F1/F1b)
Server PHP: ActivityAgreementAdapter::propose normalises `boundedQuantity` before the closed key whitelist
(collect kinds: alias to quantity; other kinds: drop boundedQuantity/quantity). activity_prompt.php:5 stops saying "bounded quantity".
Run: `python3 apply.py <tree-root> [--check]` (idempotent, backs up as *.bak-fix14dsrv). Trees: /root/imm26/compose and lane sites /tmp/stobe-*/site.
Test: `apply_test.py <tree-root>` adds the regression checks to tests/imm26_wpE_activity_kinds_regression.php (fail before F1, pass after).
