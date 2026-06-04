#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Error: Please run with sudo."
    exit 1
fi

# Enable SysRq
echo 1 > /proc/sys/kernel/sysrq

# Flush filesystem buffers
echo s > /proc/sysrq-trigger
sleep 2

# Remount filesystems read-only
echo u > /proc/sysrq-trigger
sleep 2

# Immediate power off
echo o > /proc/sysrq-trigger
