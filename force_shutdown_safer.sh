#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Error: Please run with sudo."
    exit 1
fi

echo "Attempting normal shutdown..."
systemctl poweroff

sleep 30

echo "Normal shutdown did not complete; forcing power off..."

echo 1 > /proc/sys/kernel/sysrq
echo s > /proc/sysrq-trigger
sleep 2
echo u > /proc/sysrq-trigger
sleep 2
echo o > /proc/sysrq-trigger
