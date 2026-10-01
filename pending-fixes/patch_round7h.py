#!/usr/bin/env python3
"""Round 7h: bug 4 variant. "...you give me the vodka, I pay you three hundred cats. Deal?"
paid at once: "i pay you" is a hand-over cue and "Deal?" is judged as its own sentence.
A message that ends by asking for agreement is an offer, unless the hand-over sentence is
an explicit "here's / here you go / as promised".

Usage: patch_round7h.py <StobeServer root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
p = root / "lib/negotiation_voice.php"
t = p.read_text(encoding="utf-8")
old = """    if ($text === '') return ['reason'=>$reason] + $none;
    $cue = preg_match($cuePattern, $text) === 1;
"""
new = """    if ($text === '') return ['reason'=>$reason] + $none;
    // "..., I pay you 300. Deal?" asks for agreement: an offer, unless it's an explicit "here's".
    if (preg_match("/\\b(deal|agreed|okay|ok|alright|sound good|fair|you in|yes|right)\\s*\\?\\s*$/", $trimmed)
        && !preg_match("/\\b(here'?s|here is|here are|here you go|there you go|as promised|as agreed)\\b/", $text)) {
        return ['reason'=>'offer_or_future'] + $none;
    }
    $cue = preg_match($cuePattern, $text) === 1;
"""
assert t.count(old) == 1, "anchor"
p.write_text(t.replace(old, new), encoding="utf-8")
print("patch_round7h: applied")
