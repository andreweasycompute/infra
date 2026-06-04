#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Error: Please run with sudo."
    exit 1
fi

echo "Attempting normal reboot..."
systemctl reboot

# If systemd returns but the machine does not reboot,
# wait briefly and fall back to Magic SysRq.
sleep 30

echo "Normal reboot did not complete; forcing reboot..."

echo 1 > /proc/sys/kernel/sysrq
echo s > /proc/sysrq-trigger
sleep 2
echo u > /proc/sysrq-trigger
sleep 2
echo b > /proc/sysrq-trigger
