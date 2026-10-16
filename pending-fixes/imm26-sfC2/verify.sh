#!/bin/bash
# applies apply.py to a copy of the pre-fix file (sfC-bak) and compares with the compose tree
set -e
T=$(mktemp -d); mkdir -p $T/lib; cp /root/imm26/sfC-bak/social_repair_agreements.php $T/lib/
python3 /mnt/c/KenshiModding/pending-fixes/imm26-sfC2/apply.py $T
cmp $T/lib/social_repair_agreements.php /root/imm26/compose/lib/social_repair_agreements.php && echo "APPLY-IDENTICAL to compose"
python3 /mnt/c/KenshiModding/pending-fixes/imm26-sfC2/apply.py $T
php -l $T/lib/social_repair_agreements.php
