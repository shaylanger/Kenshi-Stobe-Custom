# live-tune.sh default spec: sword S1 (edge never faces the camera) + PT30-FLIP (no elbow flip at the first wind-up after
# a draw), stroke 1. "<lhs> [step|auto] [lo|auto] [hi|auto]"; x0 = the running game's value (live_tune.py header).
# First game run (5090 livetune-s1-5090, base score 75.8): every edge-to-camera frame is in the stroke-1 swing at u 0.5-0.9
# (late strike + follow-through = keys 4 and 5), none in ready/draw -> tune the k4/k5 edge (up) vectors.
edgectol 0.03 -0.08 0.2       # edge clamp tolerance (sword-fix: <= -0.08 breaks the arc)
e1ib 0.03 0.6 0.95            # PT30 follow-through blend
elbhyst auto                  # elbow side pick hysteresis (PT30-FLIP)
swk_alt.s1_k4.ux 0.2 auto auto   # stroke-1 key 4 (end of strike, u 0.58) blade up vector = edge direction
swk_alt.s1_k4.uy 0.2 auto auto
swk_alt.s1_k4.uz 0.2 auto auto
swk_alt.s1_k5.ux 0.2 auto auto   # stroke-1 key 5 (follow-through end)
swk_alt.s1_k5.uy 0.2 auto auto
swk_alt.s1_k5.uz 0.2 auto auto
