# GPU Power-Delivery Stress Test (for the data center)

**Node:** 217.138.104.41 (Super-5090x8, 8x RTX 5090)
**No PUoW workload software is used.** This is a plain PyTorch CUDA stress tool.

## Why this test exists

Your 1-hour `gpu-fryer` 575W stress test passed, but the node still crashes
under our PUoW workload: GPU0 falls off the PCIe bus (`Xid 79`) and the driver
flags **all 8 GPUs** with `Xid 154 = Node Reboot Required`, within seconds of
total draw exceeding ~4000W.

The difference is the **power pattern**, not the workload:

- `gpu-fryer` = **steady-state** BF16 compute -> smooth, flat power draw.
- PUoW workload = **bursty** power -> repeated current spikes (di/dt) on the
  shared 12V rail / PSU.

A power-delivery system can pass a flat-load test and still fail under
transients. This tool lets you reproduce the fault **without any PUoW
workload software**, using two modes on the same hardware:

| Mode     | Power pattern                              | Expected result |
|----------|--------------------------------------------|-----------------|
| `steady` | continuous full load (like gpu-fryer)      | PASS            |
| `spike`  | synchronized burst/idle cycles (di/dt)     | reproduces the fault |

If `steady` passes but `spike` fails on the same node, the problem is the
node's power delivery handling current transients -- not the GPUs and not our
software.

## Requirements

- NVIDIA driver already installed (you have 595.71.05).
- Python 3. PyTorch with CUDA is auto-installed if missing: the runner first
  tries `pip3 install torch`, and on PEP-668 systems (Ubuntu 24.04) falls back
  to a local virtualenv at `./venv`. On Ubuntu you may need the venv package
  once: `sudo apt-get install -y python3.12-venv`. (An `nvcr.io/nvidia/pytorch`
  container also works.)
- `sudo` (to raise power limits and read the kernel log).

## How to run

```bash
cd dc_power_test
chmod +x run_power_spike_test.sh power_spike_test.py

# 1) Control run -- steady load, should PASS:
./run_power_spike_test.sh steady 900

# 2) Reproduction run -- spike load, expected to trip the fault:
./run_power_spike_test.sh spike 900
```

Each run:
1. Raises every card to its **default max power limit** (so total draw reaches
   the real ~4000-4600W envelope).
2. Launches one worker per GPU, all **synchronized** to spike at the same instant.
3. Logs per-GPU and **total** power once per second to a CSV.
4. Streams the kernel log and captures any `fallen off the bus` / `Xid` lines.
5. Prints a verdict: **PASS** (all GPUs survived) or **FAIL** (a GPU dropped /
   fell off the bus).

Tunables (edit the worker args in `run_power_spike_test.sh` if you want a
harsher transient): `--burst-ms`, `--idle-ms`, `--size`, `--dtype`.

## What the output proves

- The per-second **power CSV** shows the exact total wattage at the moment of
  failure.
- A `[DMESG] ... Xid 79 ... fallen off the bus` line in the log is the
  smoking gun: a power/PCIe physical-layer fault, independent of software.
- `steady` PASS + `spike` FAIL at a similar peak wattage = the node cannot
  handle synchronized current transients -> power-delivery hardware issue
  (PSU capacity / 12V distribution / PCIe-EPS cabling / backplane).

## Recovery after a FAIL

Once a GPU has fallen off the bus, software cannot recover it
(`nvidia-smi --gpu-reset`, PCIe remove/rescan, bus reset all fail). The driver
itself requests `Node Reboot Required` -- please **power-cycle the node**.
