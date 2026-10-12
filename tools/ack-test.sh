#!/usr/bin/env bash
# Probes the touchpad's I2C address 20 times (every 0.25 s) and prints S when it
# answers and . when it does not. A healthy touchpad answers every time; after a
# warm reboot at 100 kHz an affected one answers only some of the time or never.
#
# Only works while no driver is bound to the touchpad (i.e. when it is broken).
# Needs root and i2c-tools:  sudo apt install i2c-tools && sudo ./tools/ack-test.sh
set -u
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }
command -v i2cget >/dev/null || { echo "Install i2c-tools first: sudo apt install i2c-tools"; exit 1; }

CLIENT=/sys/bus/i2c/devices/i2c-ELAN06FA:00
[[ -e $CLIENT ]] || { echo "No ELAN06FA touchpad found."; exit 1; }
if [[ -e $CLIENT/driver ]]; then
  echo "The touchpad is bound to its driver (working); this test is for when it is not."
  exit 0
fi

bus=$(basename "$(dirname "$(readlink -f "$CLIENT")")"); bus=${bus#i2c-}
# sysfs does not expose the address of ACPI-enumerated I2C clients; 0x15 is the
# ELAN06FA address in the Flex 5 14ARE05 DSDT (I2cSerialBusV2 (0x0015, ...)).
addr=${ADDR:-0x15}
modprobe i2c-dev

echo "I2C bus $bus, address $addr:"
echo -n "  "
hits=0
for i in $(seq 20); do
  if i2cget -y "$bus" "$addr" >/dev/null 2>&1; then echo -n S; hits=$((hits + 1)); else echo -n .; fi
  sleep 0.25
done
echo
echo "Answered $hits/20. A healthy touchpad answers 20/20."
