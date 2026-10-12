#!/usr/bin/env bash
# Read-only check: does this machine have the ELAN06FA touchpad, is its I2C bus
# forced to 100 kHz, did the touchpad probe in this boot, and is the fix active?
# No root needed (reading the kernel log may need membership of the adm or
# systemd-journal group).
set -u

ok()   { printf '  [ok]   %s\n' "$*"; }
bad()  { printf '  [!!]   %s\n' "$*"; }
info() { printf '  [--]   %s\n' "$*"; }

klog() { journalctl -k -b --no-pager -o cat 2>/dev/null || dmesg 2>/dev/null; }

echo "Machine"
info "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_version 2>/dev/null) ($(cat /sys/class/dmi/id/product_name 2>/dev/null)), BIOS $(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
info "kernel $(uname -r)"

echo "Touchpad"
if ls -d /sys/bus/acpi/devices/ELAN06FA:* >/dev/null 2>&1; then
  ok "ELAN06FA touchpad present in ACPI"
else
  bad "no ELAN06FA touchpad: this fix does not apply to this machine"
  exit 0
fi
client=/sys/bus/i2c/devices/i2c-ELAN06FA:00
if [[ -e $client ]]; then
  ctrl=$(basename "$(dirname "$(dirname "$(readlink -f "$client")")")")
  info "attached to I2C controller $ctrl"
fi

log=$(klog)
if [[ -z $log ]]; then
  info "cannot read the kernel log (try: sudo $0)"
elif grep -q "${ctrl:-AMDI0010}.*forcing it to 100000" <<< "$log"; then
  bad "the kernel forces this bus to 100 kHz (the ELAN06FA quirk is active)"
else
  ok "no 100 kHz quirk message for this bus"
fi

if [[ -e $client/driver ]]; then
  ok "touchpad is bound to $(basename "$(readlink -f "$client/driver")") (working)"
else
  bad "touchpad is NOT bound to a driver (not working in this boot)"
fi

prev=$(journalctl -b -1 --no-pager -o cat 2>/dev/null | grep -oE "System is (rebooting|powering down)" | tail -n 1)
[[ -n $prev ]] && info "previous boot ended with: ${prev#System is }"

echo "Fix"
installed=0
if modinfo elan06fa_400khz >/dev/null 2>&1; then
  installed=1
  ok "module elan06fa_400khz is installed for this kernel"
else
  info "module elan06fa_400khz is not installed for this kernel"
fi
if lsmod | grep -q '^elan06fa_400khz'; then
  ok "module is loaded"
elif (( installed )); then
  bad "module is installed but NOT loaded (with Secure Boot, is the DKMS signing key enrolled?)"
fi
if grep -q "elan06fa_400khz: .*100 kHz -> 400 kHz" <<< "$log"; then
  ok "bus was switched to 400 kHz in this boot"
fi
state=$(systemctl is-enabled elan06fa-400khz.service 2>/dev/null) && info "service elan06fa-400khz: $state"
journalctl -b -u elan06fa-400khz --no-pager -o cat 2>/dev/null | grep -vE "^(Starting|Finished|Stopped|Stopping) " | tail -n 1 | sed 's/^/  [--]   service said: /'
