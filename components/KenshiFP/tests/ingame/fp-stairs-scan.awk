# fp-stairs-scan.awk: pick a climbable stair line from a `fp_camera floors` reply (C05-STAIRS setup in fp-control.sh).
# Usage: awk -v by=<house y> -f fp-stairs-scan.awk <floors file>
# Prints "x y z yaw ground=G rise=R lines=N" (start on the ground floor, yaw up the stair) or a reason word.
# Ground G = the most common height among surfaces with another surface below them (a built floor over terrain; a
# wide scan also covers open terrain, which has nothing below it) (the house floor; the old "lowest height in >= 10%" picked the terrain
# under the floor, so the whole floor counted as stair cells and m50 5090 p walked along the flat floor into a
# counter, dy 0). A line is walked on the 3-unit grid: from the floor, each 3-unit step takes the highest surface
# within -2..+ST (4) of the current height; it stops at a gap, a drop, or anything ST..20 above the current height
# (wall, counter, too-low ceiling). The first two samples must be level floor (start 3+ units before the stair).
# Score = the smallest rise of the line and its two parallels 3 units to each side (the body needs the width), plus
# half the smaller rise of the parallels 6 units out (prefer the middle of the stair over its edge by a railing).
# Steps up to ST=4 per 3 units: a real Storm House stair rises 3 per 3; the round 6-per-3 hump beside it is not
# walkable (m50 5090 S: the old 7.5 limit picked the hump, Axima stuck after 6 units).
BEGIN { RS = ";"; ST = (step == "") ? 4 : step + 0 }
{ sub(/^.*floors/, ""); if (!match($0, /-?[0-9.]+,-?[0-9.]+:[-0-9.\/]+/)) next
  c = substr($0, RSTART, RLENGTH); split(c, a, ":"); split(a[1], xz, ","); ++n
  X[n] = xz[1] + 0; Z[n] = xz[2] + 0; NS[n] = split(a[2], ys, "/")
  for (i = 1; i <= NS[n]; i++) { y = ys[i] - by; Y[n, i] = y; b = int(y + 100.5) - 100; all[b]++; if (i < NS[n]) cnt[b]++ }
  if (n == 1 || X[n] < x0) x0 = X[n]; if (n == 1 || Z[n] < z0) z0 = Z[n] }
function cell(px, pz,   k) { k = (int((px - x0) / 3 + 100.5) - 100) SUBSEP (int((pz - z0) / 3 + 100.5) - 100); return (k in C) ? C[k] : 0 }
function climb(px, pz, fx, fz,   h, k, c, i, y, b, top) { h = G; top = 0; RK = 99
  for (k = 0; k <= 15; k++) { c = cell(px + fx * 3 * k, pz + fz * 3 * k); if (!c) break; b = -1e9
    for (i = 1; i <= NS[c]; i++) { y = Y[c, i]; if (y > h + ST && y < h + 20) return (k <= 1) ? -1 : top
      if (y >= h - 2 && y <= h + ST && y > b) b = y }
    if (b == -1e9) break
    if (k <= 1 && (b - G > 1.5 || G - b > 1.5)) return -1
    h = b; if (h - G > top) top = h - G; if (top >= 10 && RK == 99) RK = k }
  return top }
# search(g): ground g refined to the mean of the surfaces within +-1, then the best line from it (sets G L bs bx bz byaw)
function search(g,   s, m, c, i, y, k, yaw, fx, fz, r0, rk, r1, r2, r3, r4, sc, w, best) {
  s = 0; m = 0; for (c = 1; c <= n; c++) for (i = 1; i <= NS[c]; i++) { y = Y[c, i]; if (y >= g - 1 && y <= g + 1) { s += y; m++ } }
  G = m ? s / m : g; best = -1e9; L = 0; bs = -1
  for (c = 1; c <= n; c++) for (k = 0; k < 32; k++) { yaw = -3.14159 + k * 6.28318 / 32; fx = sin(yaw); fz = cos(yaw)
    r0 = climb(X[c], Z[c], fx, fz); if (r0 < 12) continue; rk = RK
    r1 = climb(X[c] + fz * 3, Z[c] - fx * 3, fx, fz); r2 = climb(X[c] - fz * 3, Z[c] + fx * 3, fx, fz)
    sc = r0; if (r1 < sc) sc = r1; if (r2 < sc) sc = r2; L++
    r3 = climb(X[c] + fz * 6, Z[c] - fx * 6, fx, fz); r4 = climb(X[c] - fz * 6, Z[c] + fx * 6, fx, fz); w = (r3 < r4) ? r3 : r4
    if (w < 0) w = 0; if (w > sc) w = sc
    if (sc + 0.5 * w - 0.01 * rk > best) { best = sc + 0.5 * w - 0.01 * rk; bs = sc; bx = X[c]; bz = Z[c]; byaw = yaw } }
  return (L && bs >= 12) }
# Ground fallback: a game-placed (world) building scan is mostly open floor/terrain with roofs and furniture over it, so
# the "surface with another below" mode is a roof (m50 5090 Hub Outlaw Quarters: ground=15.9, no line); when that mode
# finds no line, retry with the most common height overall (the floor/terrain at the stair foot: 4.5, rise 31).
END { if (n < 20) { print "few_cells " n; exit }
  for (c = 1; c <= n; c++) C[(int((X[c] - x0) / 3 + 100.5) - 100) SUBSEP (int((Z[c] - z0) / 3 + 100.5) - 100)] = c
  mx = 0; for (b in cnt) if (cnt[b] > mx) { mx = cnt[b]; g1 = b + 0 }
  ma = 0; for (b in all) if (all[b] > ma) { ma = all[b]; g2 = b + 0 }
  ok = mx ? search(g1) : 0; if (!ok && (!mx || g2 != g1)) ok = search(g2)
  if (!ok) { printf "no_stair_line ground=%.1f lines=%d best=%.1f cells=%d\n", G, L, (L ? bs : 0), n; exit }
  printf "%.1f %.1f %.1f %.4f ground=%.1f rise=%.1f lines=%d cells=%d\n", bx, by + G + 1, bz, byaw, G, bs, L, n }
