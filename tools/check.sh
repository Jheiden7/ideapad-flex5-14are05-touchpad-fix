#!/usr/bin/env bash
# Read-only check: does this machine have the ELAN06FA touchpad, is its I2C bus
# forced to 100 kHz, did the touchpad probe in this boot, and is the fix active?
# No root needed (reading the kernel log may need membership of the adm or
# systemd-journal group). Most useful right after a warm reboot.
set -u

ok()   { printf '  [ok]   %s\n' "$*"; }
bad()  { printf '  [!!]   %s\n' "$*"; }
info() { printf '  [--]   %s\n' "$*"; }

klog() { journalctl -k -b --no-pager -o cat 2>/dev/null || dmesg 2>/dev/null; }

client=/sys/bus/i2c/devices/i2c-ELAN06FA:00
model=$(cat /sys/class/dmi/id/product_version 2>/dev/null)

echo "Machine"
info "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $model ($(cat /sys/class/dmi/id/product_name 2>/dev/null)), BIOS $(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
info "kernel $(uname -r)"
if [[ $model == *"IdeaPad Flex 5 14ARE05"* ]]; then
  ok "tested model"
else
  info "untested model: the module only loads here with force=1 (see the README)"
fi

echo "Touchpad"
if ! ls -d /sys/bus/acpi/devices/ELAN06FA:* >/dev/null 2>&1; then
  bad "no ELAN06FA touchpad: this fix does not apply to this machine"
  echo
  echo "Verdict: not affected (no ELAN06FA touchpad)."
  exit 0
fi
ok "ELAN06FA touchpad present in ACPI"
ctrl=""
if [[ -e $client ]]; then
  ctrl=$(basename "$(dirname "$(dirname "$(readlink -f "$client")")")")
  info "attached to I2C controller $ctrl"
fi

log=$(klog)
forced=0 switched=0
grep -q "${ctrl:-AMDI0010}: .*forcing it to 100000" <<< "$log" && forced=1
grep -q "elan06fa_400khz: .*100 kHz -> 400 kHz" <<< "$log" && switched=1
if [[ -z $log ]]; then
  info "cannot read the kernel log (try: sudo $0)"
elif (( forced && switched )); then
  ok "the kernel forced this bus to 100 kHz at boot; the fix switched it to 400 kHz"
elif (( forced )); then
  bad "the kernel forces this bus to 100 kHz (the quirk behind the problem)"
else
  ok "this kernel does not force this bus to 100 kHz"
fi

working=0
if [[ -e $client/driver ]]; then
  working=1
  ok "touchpad is bound to $(basename "$(readlink -f "$client/driver")") (working)"
else
  bad "touchpad is NOT bound to a driver (not working in this boot)"
fi

prev=$(journalctl -b -1 --no-pager -o cat 2>/dev/null | grep -oE "System is (rebooting|powering down)" | tail -n 1)
[[ -n $prev ]] && info "previous boot ended with: ${prev#System is }"

echo "Fix"
installed=0 loaded=0
if modinfo elan06fa_400khz >/dev/null 2>&1; then
  installed=1
  ok "module elan06fa_400khz is installed for this kernel"
else
  info "module elan06fa_400khz is not installed for this kernel"
fi
if lsmod | grep -q '^elan06fa_400khz'; then
  loaded=1
  ok "module is loaded"
elif (( installed )); then
  bad "module is installed but NOT loaded (with Secure Boot, is the DKMS signing key enrolled?)"
fi
state=$(systemctl is-enabled elan06fa-400khz.service 2>/dev/null) && info "service elan06fa-400khz: $state"
journalctl -b -u elan06fa-400khz --no-pager -o cat 2>/dev/null | grep -vE "^(Starting|Finished|Stopped|Stopping) |Deactivated" | tail -n 1 | sed 's/^/  [--]   service said: /'

echo
if (( !forced )) && [[ -n $log ]]; then
  echo "Verdict: this kernel keeps the firmware's bus speed; the fix is not needed."
elif (( working && switched )); then
  echo "Verdict: affected, and the fix is working (touchpad at 400 kHz)."
elif (( working )); then
  echo "Verdict: touchpad working at 100 kHz. If it fails after a warm reboot, this machine is affected."
elif (( loaded || installed )); then
  echo "Verdict: affected, and the fix did not recover the touchpad in this boot (see the service message)."
else
  echo "Verdict: affected (bus forced to 100 kHz, touchpad not probed); the fix is not installed."
fi
