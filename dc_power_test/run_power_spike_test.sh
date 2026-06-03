#!/usr/bin/env bash
#
# GPU power-delivery stress test runner  --  NO PUoW workload software involved.
#
# Drives ALL GPUs at once and compares two power patterns:
#   steady : continuous full-load compute (behaves like gpu-fryer)  -> expected PASS
#   spike  : synchronized burst/idle cycles (di/dt current transients) -> reproduces fault
#
# It removes power caps so cards reach their default max (to recreate the real
# >4000W total draw), logs per-GPU + total power once per second, watches the
# kernel log for "GPU has fallen off the bus" (Xid 79), and prints a verdict.
#
# Usage:
#   ./run_power_spike_test.sh spike  900     # spike mode, 15 min   (reproduction)
#   ./run_power_spike_test.sh steady 900     # steady mode, 15 min  (control / sanity)
#
set -uo pipefail

MODE="${1:-spike}"
DURATION="${2:-900}"
HERE="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$HERE/result_${STAMP}_${MODE}.log"
PWRCSV="$HERE/power_${STAMP}_${MODE}.csv"

log() { echo "$@" | tee -a "$LOG"; }

log "=== GPU power-delivery stress test  (mode=$MODE, duration=${DURATION}s) ==="
log "host: $(hostname)   date: $(date)"
nvidia-smi --query-gpu=index,name,driver_version,power.max_limit --format=csv | tee -a "$LOG"

# 1) Resolve a CUDA-enabled Python (PyTorch). Handles Ubuntu PEP-668 via venv.
PY="python3"
if "$PY" -c "import torch" 2>/dev/null; then
  :
elif [ -x "$HERE/venv/bin/python" ] && "$HERE/venv/bin/python" -c "import torch" 2>/dev/null; then
  PY="$HERE/venv/bin/python"
else
  log "PyTorch not found -- setting up environment and installing torch..."
  if pip3 install --quiet torch 2>/dev/null && python3 -c "import torch" 2>/dev/null; then
    PY="python3"
  else
    python3 -m venv "$HERE/venv" || { log "ERROR: python3-venv missing (apt install python3-venv)"; exit 3; }
    "$HERE/venv/bin/pip" install --quiet --upgrade pip
    "$HERE/venv/bin/pip" install torch || { log "ERROR: could not install torch."; exit 3; }
    PY="$HERE/venv/bin/python"
  fi
fi
log "Using Python: $PY"
"$PY" -c "import torch;print('torch', torch.__version__, 'cuda', torch.cuda.is_available())" 2>&1 | tee -a "$LOG"

# 2) Remove power caps: set every card to its own max limit (recreate real total draw)
sudo nvidia-smi -pm 1 >/dev/null 2>&1
for i in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
  MAXW=$(nvidia-smi -i "$i" --query-gpu=power.max_limit --format=csv,noheader,nounits)
  sudo nvidia-smi -i "$i" -pl "${MAXW%.*}" >/dev/null 2>&1
done
log "Power limits raised to per-card maximum."

# 3) Background watcher: kernel log for fall-off-bus / Xid
( sudo dmesg -W 2>/dev/null \
    | grep --line-buffered -iE "fallen off the bus|GPU is lost|Node Reboot Required|Xid" \
    | while IFS= read -r line; do echo "[DMESG] $line" | tee -a "$LOG"; done ) &
DMESG_PID=$!

# 4) Background power logger (1 Hz): timestamp,total_W,per-gpu...
IDX_CSV=$(nvidia-smi --query-gpu=index --format=csv,noheader | paste -sd, -)
echo "unix_ts,total_W,${IDX_CSV}" > "$PWRCSV"
( while true; do
    DRAWS=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits | paste -sd, -)
    TOT=$(echo "$DRAWS" | awk -F, '{s=0; for(i=1;i<=NF;i++) s+=$i; printf "%.1f", s}')
    echo "$(date +%s),${TOT},${DRAWS}" >> "$PWRCSV"
    sleep 1
  done ) &
LOG_PID=$!

# 5) Launch one worker per visible GPU, synchronized start (+5s)
NGPU=$(nvidia-smi --query-gpu=index --format=csv,noheader | wc -l | tr -d ' ')
START=$(python3 -c "import time;print(time.time()+5)")
log "Launching $NGPU workers (synchronized start in 5s)..."
PIDS=()
for i in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
  CUDA_VISIBLE_DEVICES="$i" "$PY" "$HERE/power_spike_test.py" \
    --mode "$MODE" --duration "$DURATION" --start-epoch "$START" \
    --burst-ms 250 --idle-ms 150 --size 8192 --dtype bf16 >>"$LOG" 2>&1 &
  PIDS+=($!)
done

# 6) Wait for all workers
FAIL=0
for p in "${PIDS[@]}"; do wait "$p" || FAIL=1; done
sleep 2
kill "$DMESG_PID" "$LOG_PID" 2>/dev/null

# 7) Verdict
log "=== RESULT ==="
VIS=$(nvidia-smi --query-gpu=index --format=csv,noheader 2>&1 | grep -cE '^[0-9]')
PEAK=$(tail -n +2 "$PWRCSV" | cut -d, -f2 | sort -n | tail -1)
log "Peak total power observed: ${PEAK:-?} W"
log "GPUs visible after test:   ${VIS} / ${NGPU}"
if sudo dmesg | grep -qiE "fallen off the bus"; then
  log "VERDICT: *** FAIL *** -- a GPU fell off the PCIe bus (Xid 79). Power-delivery fault REPRODUCED."
elif [ "$VIS" -lt "$NGPU" ] || [ "$FAIL" -ne 0 ]; then
  log "VERDICT: *** FAIL *** -- GPU(s) lost or a worker crashed during the run."
else
  log "VERDICT: PASS -- all ${NGPU} GPUs survived at peak ${PEAK:-?} W."
fi
log "Full log:  $LOG"
log "Power CSV: $PWRCSV"
