#!/usr/bin/env python3
"""
Standalone GPU power-delivery stress test  --  NO PUoW workload software involved.

Purpose
-------
Reproduce a power-delivery / di-dt (current transient) fault by driving every
GPU with SYNCHRONIZED power BURSTS ("spike" mode), as opposed to flat
steady-state compute ("steady" mode, which behaves like gpu-fryer).

This is one per-GPU worker. It is normally launched once per GPU by
run_power_spike_test.sh, with CUDA_VISIBLE_DEVICES pinning each worker to one
GPU and a shared --start-epoch so all GPUs spike at the same instant (worst
case for a shared 12V rail / PSU).

Dependencies: Python 3 + PyTorch with CUDA. Nothing else.
"""
import argparse
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["spike", "steady"], default="spike",
                    help="spike = burst/idle cycles (di/dt); steady = continuous load")
    ap.add_argument("--duration", type=float, default=600.0, help="seconds")
    ap.add_argument("--burst-ms", type=float, default=250.0, help="compute burst length")
    ap.add_argument("--idle-ms", type=float, default=150.0, help="idle gap (spike mode only)")
    ap.add_argument("--size", type=int, default=8192, help="square matrix dimension")
    ap.add_argument("--dtype", choices=["fp16", "bf16", "fp32"], default="bf16")
    ap.add_argument("--start-epoch", type=float, default=0.0,
                    help="unix time at which all workers begin (synchronization)")
    args = ap.parse_args()

    try:
        import torch
    except Exception as e:  # noqa
        print(f"ERROR: PyTorch import failed: {e}", file=sys.stderr)
        sys.exit(2)

    if not torch.cuda.is_available():
        print("ERROR: CUDA not available to PyTorch", file=sys.stderr)
        sys.exit(2)

    dev = torch.device("cuda:0")  # CUDA_VISIBLE_DEVICES already pins the physical GPU
    dt = {"fp16": torch.float16, "bf16": torch.bfloat16, "fp32": torch.float32}[args.dtype]
    n = args.size

    name = torch.cuda.get_device_name(0)
    a = torch.randn((n, n), device=dev, dtype=dt)
    b = torch.randn((n, n), device=dev, dtype=dt)
    c = torch.empty((n, n), device=dev, dtype=dt)  # noqa: F841

    period = (args.burst_ms + args.idle_ms) / 1000.0
    burst = args.burst_ms / 1000.0

    # Align to the shared start epoch so every GPU bursts together.
    if args.start_epoch > 0:
        while time.time() < args.start_epoch:
            time.sleep(0.005)

    t_end = time.time() + args.duration
    cycles = 0
    while time.time() < t_end:
        cyc_start = time.time()
        burst_end = cyc_start + burst
        # ---- BURST: hammer tensor-core matmuls to pull peak power ----
        while time.time() < burst_end:
            for _ in range(20):
                c = torch.matmul(a, b)  # noqa: F841
            torch.cuda.synchronize()
        if args.mode == "spike":
            # ---- IDLE: let power collapse, creating the di/dt transient ----
            torch.cuda.synchronize()
            rem = period - (time.time() - cyc_start)
            if rem > 0:
                time.sleep(rem)
        cycles += 1

    print(f"[{name}] completed mode={args.mode} cycles={cycles}", flush=True)


if __name__ == "__main__":
    main()
