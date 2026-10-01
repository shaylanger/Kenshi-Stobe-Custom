<?php
require __DIR__ . '/../lib/bootstrap.php';
$ok=0;$bad=0; function t($n,$c,$d=null){global $ok,$bad; if($c){$ok++;echo "PASS $n\n";}else{$bad++;echo "FAIL $n ".json_encode($d)."\n";}}
// 36
foreach ([
 ["Four hundred then. You take off your Iron Hat, you keep it. Deal?", true],
 ["Four hundred then.", true],
 ["500 it is", true],
 ["I killed 3 bandits today, deal with it.", false],
 ["Deal with it.", false],
 ["Nice weather in the Hub today.", false],
] as [$m,$exp]) t("36 offer: $m", stobeNegLooksLikeSocialOffer($m) === $exp, stobeNegLooksLikeSocialOffer($m));
// 35 sentence filter with no open deal returns null (no crash)
t("35 no open deal", stobeDealProgressAmountCheck("Three hundred cats?", "NoSuchNpcR15", "300 cats") === null);
// 37 remember/take
stobeDealRememberUnrecordedAgreement('R15Npc', 'Three hundred cats, deal?', 'Make it four hundred.', 'COUNTER');
$n = stobeDealTakeUnrecordedAgreement('R15Npc', 'Shay');
t("37 counter note", str_contains($n, 'counter-offer') && str_contains($n, 'COUNTER'), $n);
t("37 one-shot", stobeDealTakeUnrecordedAgreement('R15Npc', 'Shay') === '');
stobeDealRememberUnrecordedAgreement('R15Npc', 'x', 'Fine.');
t("30 still accept", str_contains(stobeDealTakeUnrecordedAgreement('R15Npc','Shay'), 'ACCEPT'));
// 42 pending notes (none for unknown npc)
t("42 notes empty", stobeNegPendingDirectiveNotes('NoSuchNpcR15') === []);
echo "ok=$ok bad=$bad\n";
