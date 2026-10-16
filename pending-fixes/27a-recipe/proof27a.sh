#!/usr/bin/env bash
# proof27a.sh <live rowtools dir> <patched rowtools dir>   fake evidence (control 200->200, pre 200->60, post 200->66, hire has_contract=1, hours_left 24.0 -> 23.1)
# through the OLD (live, unpatched) and the NEW c_27a. Expected: old = RESULT 27-a FAIL, new = RESULT 27-a PASS.
E=$(mktemp -d)
printf 'Cind [Hungry Bandit] has_contract=1 package=Bodyguard hirer=Shay hours_left=24.0\n' > "$E/bg_set.txt"
cp "$E/bg_set.txt" "$E/bg_pre.txt"; printf 'Cind [Hungry Bandit] has_contract=1 package=Bodyguard hirer=Shay hours_left=23.1\n' > "$E/bg_post.txt"
echo 'none' > "$E/state_pre.txt"; echo 'none' > "$E/state_post.txt"; echo 'none' > "$E/state_after_chase.txt"
echo '200|200' > "$E/chase_ctrl.txt"; echo '200|60' > "$E/chase_pre.txt"; echo '200|66' > "$E/chase_post.txt"
for d in "$1" "$2"; do echo "== $d"; python3 -I "$d/reloadcheck_a.py" 27-a "$E" | cut -c1-400; done
