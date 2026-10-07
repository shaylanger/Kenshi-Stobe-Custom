# fp-yaw-free.awk: static-obstacle check of the 16 pick_yaw headings from `fp_camera floors` replies around a walker.
# Usage: awk -v px=<x> -v pz=<z> -f fp-yaw-free.awk <floors file(s)>
# Prints 16 tokens "<forward>/<back>": how far (units) each heading's walk line is free ahead (max 130) and behind
# (max 30). The line follows the top surface in 3-unit samples (nearest scanned cell) and is blocked where the top
# rises more than 6 over one sample (rock, wall, crate, tree). m50 5090 p/s + 4080 b42: heading -2.7489 from Axima's
# fixture spot always ended at the same place 54 units on, 24 deg off, with no character near (static obstacle;
# pick_yaw only knew characters). Same headings as pick_yaw: y = -pi + k*2pi/16, direction (sin y, cos y).
BEGIN { RS = ";" }
{ sub(/^.*floors/, ""); if (!match($0, /-?[0-9.]+,-?[0-9.]+:[-0-9.\/]+/)) next
  c = substr($0, RSTART, RLENGTH); split(c, a, ":"); split(a[1], xz, ","); split(a[2], ys, "/"); ++n
  X[n] = xz[1] + 0; Z[n] = xz[2] + 0; T[n] = ys[1] + 0
  if (n == 1 || X[n] < x0) x0 = X[n]; if (n == 1 || Z[n] < z0) z0 = Z[n]
  if (n == 2 && !sp) sp = (X[2] != X[1]) ? X[2] - X[1] : Z[2] - Z[1]; if (sp < 0) sp = -sp }
function top(qx, qz,   k) { k = (int((qx - x0) / sp + 100.5) - 100) SUBSEP (int((qz - z0) / sp + 100.5) - 100); return (k in C) ? T[C[k]] : "" }
function free(fx, fz, dir, lim,   t, h, y) { h = top(px, pz); if (h == "") return 0
  for (t = 3; t <= lim; t += 3) { y = top(px + dir * fx * t, pz + dir * fz * t); if (y == "") return t - 3
    if (y - h > 6) return t - 3; h = y }
  return lim }
END { if (n < 20 || !sp) { for (k = 0; k < 16; k++) printf "%s130/30", (k ? " " : ""); print ""; exit }   # no scan: no veto
  for (c = 1; c <= n; c++) C[(int((X[c] - x0) / sp + 100.5) - 100) SUBSEP (int((Z[c] - z0) / sp + 100.5) - 100)] = c
  for (k = 0; k < 16; k++) { y = -3.14159 + k * 6.28318 / 16; fx = sin(y); fz = cos(y)
    printf "%s%d/%d", (k ? " " : ""), free(fx, fz, 1, 130), free(fx, fz, -1, 30) }
  print "" }
