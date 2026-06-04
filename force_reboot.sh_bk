#!/usr/bin/env bash
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run with sudo."
    exit 1
fi
echo 1 > /proc/sys/kernel/sysrq
echo s > /proc/sysrq-trigger
sleep 1
echo u > /proc/sysrq-trigger
sleep 1
echo b > /proc/sysrq-trigger
