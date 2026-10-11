# live-tune spec (sword-judge 2026-10-11): S1 edge clamp strength in the E1 lead (eclsw) + tolerance (edgectol), scored in game.
# Trade-off seen: clamp on (eclsw 1, edgectol -0.08) -> 5090 stroke-1 wrist bend 53.5 > 50 at u .56-.70; clamp off (eclsw 0,
# edgectol 0) -> wb 46 but 1-4 ready frames right after a stroke-3 swing with the edge toward the camera (-0.09) in 10/35 evals.
# The score has both terms (wb, s1 rest edge) + gates; run per stroke (1 and 3).
eclsw 0.25 0 1
edgectol 0.03 -0.08 0.04
