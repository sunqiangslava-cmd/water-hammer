#!/usr/bin/env python3
"""Simple 1D water-hammer simulator using a characteristic-style update.

Model assumptions (intentionally lightweight):
- Liquid compressibility represented by wave speed a.
- Uniform pipe section.
- Optional steady friction for initial condition only.
- Upstream constant-head reservoir.
- Downstream valve with linear closure profile.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass


G = 9.81  # m/s^2


@dataclass
class SimulationConfig:
    length: float = 1000.0
    diameter: float = 0.5
    wave_speed: float = 1200.0
    reservoir_head: float = 100.0
    initial_discharge: float = 0.2
    darcy_friction: float = 0.02
    segments: int = 40
    total_time: float = 10.0
    valve_close_time: float = 2.0
    output_csv: str = "water_hammer_output.csv"


def area(diameter: float) -> float:
    from math import pi

    return pi * (diameter**2) / 4.0


def valve_open_ratio(t: float, close_time: float) -> float:
    if close_time <= 0:
        return 0.0
    return max(0.0, 1.0 - t / close_time)


def run_simulation(cfg: SimulationConfig) -> list[dict[str, float]]:
    n = cfg.segments
    if n < 2:
        raise ValueError("segments must be >= 2")

    dx = cfg.length / n
    dt = dx / cfg.wave_speed  # Courant~=1 for this scheme
    steps = int(cfg.total_time / dt)

    A = area(cfg.diameter)
    B = cfg.wave_speed / (G * A)

    velocity0 = cfg.initial_discharge / A
    hf_total = cfg.darcy_friction * cfg.length / cfg.diameter * (velocity0**2) / (2 * G)

    H = [cfg.reservoir_head - hf_total * (i / n) for i in range(n + 1)]
    Q = [cfg.initial_discharge for _ in range(n + 1)]

    records: list[dict[str, float]] = []

    for k in range(steps + 1):
        t = k * dt

        head_min = min(H)
        head_max = max(H)
        q_down = Q[-1]
        h_down = H[-1]
        records.append(
            {
                "time_s": t,
                "downstream_head_m": h_down,
                "downstream_discharge_m3s": q_down,
                "min_head_m": head_min,
                "max_head_m": head_max,
            }
        )

        H_new = H.copy()
        Q_new = Q.copy()

        # Interior nodes
        for i in range(1, n):
            H_new[i] = 0.5 * (H[i - 1] + H[i + 1]) + 0.5 * B * (Q[i - 1] - Q[i + 1])
            Q_new[i] = 0.5 * (Q[i - 1] + Q[i + 1]) + 0.5 * (1 / B) * (H[i - 1] - H[i + 1])

        # Upstream boundary: constant head reservoir
        cm = H[1] - B * Q[1]
        H_new[0] = cfg.reservoir_head
        Q_new[0] = (H_new[0] - cm) / B

        # Downstream boundary: valve closure with prescribed flow ratio
        cp = H[n - 1] + B * Q[n - 1]
        q_valve = cfg.initial_discharge * valve_open_ratio(t + dt, cfg.valve_close_time)
        Q_new[n] = q_valve
        H_new[n] = cp - B * Q_new[n]

        H, Q = H_new, Q_new

    return records


def write_csv(path: str, rows: list[dict[str, float]]) -> None:
    if not rows:
        return
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Water hammer simulation (simple 1D model)")
    p.add_argument("--length", type=float, default=1000.0, help="Pipe length (m)")
    p.add_argument("--diameter", type=float, default=0.5, help="Pipe diameter (m)")
    p.add_argument("--wave-speed", type=float, default=1200.0, help="Pressure wave speed (m/s)")
    p.add_argument("--reservoir-head", type=float, default=100.0, help="Upstream reservoir head (m)")
    p.add_argument("--initial-discharge", type=float, default=0.2, help="Initial steady flow (m^3/s)")
    p.add_argument("--darcy-friction", type=float, default=0.02, help="Darcy friction factor for initial head loss")
    p.add_argument("--segments", type=int, default=40, help="Number of pipe segments")
    p.add_argument("--total-time", type=float, default=10.0, help="Total simulation time (s)")
    p.add_argument("--valve-close-time", type=float, default=2.0, help="Linear valve closure time (s)")
    p.add_argument("--output-csv", type=str, default="water_hammer_output.csv", help="CSV output path")
    return p


def main() -> None:
    args = build_parser().parse_args()
    cfg = SimulationConfig(
        length=args.length,
        diameter=args.diameter,
        wave_speed=args.wave_speed,
        reservoir_head=args.reservoir_head,
        initial_discharge=args.initial_discharge,
        darcy_friction=args.darcy_friction,
        segments=args.segments,
        total_time=args.total_time,
        valve_close_time=args.valve_close_time,
        output_csv=args.output_csv,
    )

    rows = run_simulation(cfg)
    write_csv(cfg.output_csv, rows)

    A = area(cfg.diameter)
    v0 = cfg.initial_discharge / A
    delta_h_joukowsky = cfg.wave_speed * v0 / G

    peak = max(r["max_head_m"] for r in rows)
    trough = min(r["min_head_m"] for r in rows)

    print("=== Water Hammer Simulation Completed ===")
    print(f"Output CSV: {cfg.output_csv}")
    print(f"Time steps: {len(rows)}")
    print(f"Peak head in pipe: {peak:.3f} m")
    print(f"Minimum head in pipe: {trough:.3f} m")
    print(f"Joukowsky estimate (full stop): +{delta_h_joukowsky:.3f} m")


if __name__ == "__main__":
    main()
