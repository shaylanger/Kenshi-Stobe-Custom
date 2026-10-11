# live-tune.sh default spec: sword S1 (edge never faces the camera) + PT30-FLIP (no elbow flip at the first wind-up after
# a draw), stroke 1. "<lhs> [step|auto] [lo|auto] [hi|auto]"; x0 = the running game's value (live_tune.py header).
# S1 = rest states only (STATUS.md R7); the first 2026-10-11 runs scored swing frames by mistake. With the rest-only scorer
# the installed build (base tables 38943ca5) scores 0 on the 5090 (S1 + PT30-FLIP + gates); k4/k5 knobs kept for PT30/E1.
edgectol 0.03 -0.08 0.2       # edge clamp tolerance (sword-fix: <= -0.08 breaks the arc)
e1ib 0.03 0.6 0.95            # PT30 follow-through blend
elbhyst auto                  # elbow side pick hysteresis (PT30-FLIP)
swk_alt.s1_k4.ux 0.2 auto auto   # stroke-1 key 4 (end of strike, u 0.58) blade up vector = edge direction
swk_alt.s1_k4.uy 0.2 auto auto
swk_alt.s1_k4.uz 0.2 auto auto
swk_alt.s1_k5.ux 0.2 auto auto   # stroke-1 key 5 (follow-through end)
swk_alt.s1_k5.uy 0.2 auto auto
swk_alt.s1_k5.uz 0.2 auto auto
