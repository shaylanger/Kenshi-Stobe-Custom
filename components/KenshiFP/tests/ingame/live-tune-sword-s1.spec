# live-tune.sh default spec: sword S1 (edge never faces the camera) + PT30-FLIP (no elbow flip at the first wind-up after
# a draw), stroke 1. "<lhs> [step|auto] [lo|auto] [hi|auto]"; x0 = the running game's value (live_tune.py header).
edgectol 0.03 -0.08 0.2       # edge clamp tolerance (sword-fix: <= -0.08 breaks the arc)
e1ib 0.03 0.6 0.95            # PT30 follow-through blend
elbhyst auto                  # elbow side pick hysteresis (PT30-FLIP)
swk_alt.s1_k2.ux 0.15 auto auto   # stroke-1 key 2 (wind-up top) blade up vector = edge direction
swk_alt.s1_k2.uz 0.15 auto auto
swk_alt.s1_k3.ux 0.15 auto auto   # stroke-1 key 3 (strike) edge direction
swk_alt.s1_k3.uz 0.15 auto auto
