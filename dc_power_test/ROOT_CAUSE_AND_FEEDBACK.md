# Root Cause: Power Delivery Cannot Handle Current Transients (di/dt)

**Node:** 217.138.104.41 (Super-5090x8, 8x RTX 5090, driver 595.71.05)

This document explains the repeated node crash and why the previous
"gpu-fryer 575W passed" result does NOT cover the actual failure condition.
Please read this before closing the ticket.

## The fault signature

Under real workload, within seconds:

- **GPU0 (0000:01:00.0) falls off the PCIe bus -> `Xid 79`**
- The driver then flags **all 8 GPUs with `Xid 154 = Node Reboot Required`**

This is a **power / PCIe physical-layer fault**, not a software or GPU defect.
No software recovery works (`nvidia-smi --gpu-reset`, PCIe remove/rescan, soft
reboot all fail). Only a **hardware power cycle** recovers GPU0.

## The real cause: current transients (di/dt), not total wattage

We ran two patterns on the same node, same hardware, power caps fully lifted:

| Test pattern                              | Power profile          | Peak total draw | Result                                            |
|-------------------------------------------|------------------------|-----------------|---------------------------------------------------|
| **Steady-state** (equivalent to gpu-fryer)| smooth, constant load  | **4626 W**      | **PASS** -- all 8 GPUs survived                   |
| **Bursty / synchronized spikes** (di/dt)  | rapid burst/idle cycles| **4357 W**      | **FAIL** -- GPU0 off the bus (Xid 79), all -> 154 |

The critical point: the node **survived 4626 W steady but crashed at a LOWER
4357 W when the load was bursty.** The failure is triggered by **rapid current
transients on the shared 12V rail**, not by the absolute power level. That is
exactly why a 1-hour 575W gpu-fryer test (smooth load) passes while the node
still crashes in production within seconds.

**A power-delivery system can pass a flat-load test and still fail under
transients.**

## How to reproduce it yourselves

Use the standalone PyTorch stress tool in this package (NO workload/PUoW
software involved). It lifts all power caps, drives all 8 GPUs synchronized,
logs per-second total power to CSV, watches dmesg for `Xid 79 / fallen off the
bus`, and prints PASS/FAIL. See `README_DC_POWER_TEST.md` for setup.

```bash
cd dc_power_test
./run_power_spike_test.sh steady 900   # control -- should PASS
./run_power_spike_test.sh spike  900   # reproduction -- expected to trip Xid 79
```

If `steady` passes and `spike` fails on the same node, the conclusion is
unambiguous: the node cannot handle synchronized current transients.

## What we are asking you to check

The fault points to the node's ability to handle synchronized current
transients. Please inspect the **power-delivery hardware**, NOT the GPUs:

- PSU capacity / transient response under simultaneous 8-GPU load steps
- 12V rail distribution and headroom
- PCIe / EPS power cabling and connector seating
- Backplane / riser power integrity

## Operational notes

- **After any FAIL, GPU0 cannot be recovered in software -- the node MUST be
  power-cycled.** Our control-panel power access has been revoked, so we
  currently depend on you for the reboot. Please restore that access or keep a
  technician available during testing.
- To keep the node stable in the meantime, we run all cards capped at
  **500 W (~4000 W total)**, which stays under the transient failure threshold.
  **This is a workaround, not a fix** -- the underlying power-delivery
  limitation remains.
