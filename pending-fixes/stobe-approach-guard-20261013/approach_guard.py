"""Fail-closed, transport-agnostic guard for one-axis NPC approach legs.

This module contains no KAH, shell, network, game, or rig transport. A caller
must supply a fresh snapshot provider and a movement callback. The provider is
called again immediately before every leg; only a validated snapshot can reach
the callback.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
import time
from typing import Callable, Optional


@dataclass(frozen=True)
class PositionSnapshot:
    player_id: str
    target_id: str
    player_x: float
    player_y: float
    player_z: float
    target_x: float
    target_y: float
    target_z: float
    started_at: float
    captured_at: float


@dataclass(frozen=True)
class Leg:
    axis: str
    direction: int
    distance: float


@dataclass(frozen=True)
class ApproachResult:
    status: str
    reason: str
    legs: int
    final_distance: Optional[float]


class SnapshotRejected(ValueError):
    pass


def _validate_snapshot(
    snapshot: object,
    *,
    expected_player_id: str,
    expected_target_id: str,
    now: float,
    max_age_seconds: float,
) -> PositionSnapshot:
    if not isinstance(snapshot, PositionSnapshot):
        raise SnapshotRejected("missing or malformed position snapshot")
    if not snapshot.player_id or snapshot.player_id != expected_player_id:
        raise SnapshotRejected("player identity missing or mismatched")
    if not snapshot.target_id or snapshot.target_id != expected_target_id:
        raise SnapshotRejected("target identity missing or mismatched")
    values = (snapshot.player_x, snapshot.player_y, snapshot.player_z,
              snapshot.target_x, snapshot.target_y, snapshot.target_z,
              snapshot.started_at, snapshot.captured_at)
    if any(not isinstance(v, (int, float)) or not math.isfinite(v) for v in values):
        raise SnapshotRejected("snapshot contains a missing or non-finite value")
    age = now - snapshot.captured_at
    acquisition_span = snapshot.captured_at - snapshot.started_at
    acquisition_age = now - snapshot.started_at
    if (age < 0 or age > max_age_seconds or acquisition_span < 0
            or acquisition_span > max_age_seconds or acquisition_age < 0
            or acquisition_age > max_age_seconds):
        raise SnapshotRejected("snapshot or coordinate acquisition is stale or from the future")
    return snapshot


def distance(snapshot: PositionSnapshot) -> float:
    return math.sqrt((snapshot.target_x - snapshot.player_x) ** 2
                     + (snapshot.target_y - snapshot.player_y) ** 2
                     + (snapshot.target_z - snapshot.player_z) ** 2)


def _next_leg(snapshot: PositionSnapshot, *, radius: float, max_leg: float) -> Leg:
    dx = snapshot.target_x - snapshot.player_x
    dz = snapshot.target_z - snapshot.player_z
    dy = snapshot.target_y - snapshot.player_y
    axis = "x" if abs(dx) >= abs(dz) else "z"
    delta = dx if axis == "x" else dz
    other_horizontal = dz if axis == "x" else dx
    other = math.hypot(other_horizontal, dy)

    # Aim one raw unit inside the radius where this axis can reach it. If the
    # perpendicular offset alone exceeds the radius, make a bounded approach
    # along the dominant axis and remeasure before considering another leg.
    inner = max(0.0, radius - 1.0)
    if abs(other) < inner:
        boundary = math.sqrt(max(0.0, inner * inner - other * other))
        needed = max(1.0, abs(delta) - boundary)
    else:
        needed = max(1.0, abs(delta))
    # KAH walktime accepts 2..500 units. Rounding a tiny final correction up
    # to its two-unit minimum is safe: it is only considered from a fresh
    # snapshot strictly outside the stop radius, then remeasured before a
    # possible follow-up leg.
    return Leg(axis=axis, direction=1 if delta > 0 else -1,
               distance=min(max_leg, max(2.0, needed)))


def walktime_arguments(leg: Leg) -> list[str]:
    """Return safe argument tokens for the documented `walktime @player` call.

    This formats only a validated Leg; it does not launch a process or send a
    command. A transport wrapper should pass these as argument tokens, not
    concatenate untrusted text into a shell command.
    """
    if leg.axis not in ("x", "z") or leg.direction not in (-1, 1):
        raise ValueError("invalid leg axis or direction")
    if not math.isfinite(leg.distance) or not (2.0 <= leg.distance <= 500.0):
        raise ValueError("walktime distance must be within 2..500")
    signed_axis = ("+" if leg.direction > 0 else "-") + leg.axis
    return ["walktime", "@player", format(leg.distance, ".6g"), signed_axis, "walk"]


def guarded_approach(
    read_snapshot: Callable[[], PositionSnapshot],
    issue_leg: Callable[[Leg], None],
    *,
    expected_player_id: str,
    expected_target_id: str,
    radius: float = 80.0,
    max_leg: float = 100.0,
    max_legs: int = 12,
    max_age_seconds: float = 2.0,
    clock: Callable[[], float] = time.monotonic,
) -> ApproachResult:
    """Approach with fresh gating immediately before every bounded leg.

    `issue_leg` is called at most once per accepted fresh snapshot. It must
    synchronously report completion (or raise). No movement is proposed when
    the measured target distance is already within `radius` raw units.
    """
    if not expected_player_id or not expected_target_id:
        return ApproachResult("ABORT", "expected identity is empty", 0, None)
    if (not math.isfinite(radius) or radius <= 0 or not math.isfinite(max_leg)
            or max_leg < 2 or max_leg > 500 or not isinstance(max_legs, int)
            or isinstance(max_legs, bool) or max_legs < 0
            or not math.isfinite(max_age_seconds) or max_age_seconds <= 0):
        return ApproachResult("ABORT", "invalid guard limits", 0, None)

    issued = 0
    final_distance: Optional[float] = None
    while issued <= max_legs:
        try:
            sample = _validate_snapshot(
                read_snapshot(), expected_player_id=expected_player_id,
                expected_target_id=expected_target_id, now=clock(),
                max_age_seconds=max_age_seconds)
        except Exception as exc:
            return ApproachResult("ABORT", str(exc), issued, final_distance)

        final_distance = distance(sample)
        if final_distance <= radius:
            return ApproachResult("IN_RANGE", "fresh distance is within radius",
                                  issued, final_distance)
        if issued == max_legs:
            return ApproachResult("ABORT", "maximum leg count reached",
                                  issued, final_distance)

        if sample.target_x == sample.player_x and sample.target_z == sample.player_z:
            return ApproachResult("ABORT", "no horizontal x/z approach vector",
                                  issued, final_distance)

        leg = _next_leg(sample, radius=radius, max_leg=max_leg)
        if not (0 < leg.distance <= max_leg):
            return ApproachResult("ABORT", "computed leg is outside bounds",
                                  issued, final_distance)
        try:
            issue_leg(leg)
        except Exception as exc:
            return ApproachResult("ABORT", "movement callback failed: %s" % exc,
                                  issued, final_distance)
        issued += 1

    return ApproachResult("ABORT", "maximum leg count reached", issued,
                          final_distance)
