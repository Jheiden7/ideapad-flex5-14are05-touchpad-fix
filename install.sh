#!/usr/bin/env bash
# Install or remove the ELAN06FA 400 kHz touchpad fix: a DKMS kernel module
# (signed automatically with the system MOK key, so it works with Secure Boot)
# plus a boot service that re-probes the touchpad.
#
# Usage: sudo ./install.sh [install|uninstall]
set -euo pipefail

NAME=elan06fa-400khz
SRC=$(cd "$(dirname "$0")" && pwd)
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$SRC/module/dkms.conf")
MOK_DER=/var/lib/shim-signed/mok/MOK.der

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0 ${1:-install}"; exit 1; }

# Removes every DKMS version of the module (also older releases).
remove_dkms() {
  local v
  for v in $(dkms status -m "$NAME" 2>/dev/null | sed -n "s|^$NAME/\([^,]*\),.*|\1|p" | sort -u); do
    dkms remove -m "$NAME" -v "$v" --all >/dev/null 2>&1 || true
    rm -rf "/usr/src/$NAME-$v"
  done
}

check_secure_boot() {
  command -v mokutil >/dev/null || return 0
  mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled" || return 0
  if [[ -f $MOK_DER ]] && mokutil --test-key "$MOK_DER" 2>/dev/null | grep -q "already enrolled"; then
    echo "Secure Boot is enabled and the DKMS signing key (MOK) is enrolled."
  else
    cat <<EOF

WARNING: Secure Boot is enabled but the DKMS signing key is not enrolled, so
the module will be refused at load time. Enroll it once:

    sudo mokutil --import $MOK_DER
    (choose a one-time password, reboot, then in the blue "MOK management"
     screen pick: Enroll MOK -> Continue -> Yes -> password -> Reboot)

EOF
  fi
}

case "${1:-install}" in
  install)
    command -v dkms >/dev/null || { echo "DKMS is missing: sudo apt install dkms"; exit 1; }
    if [[ ! -d /lib/modules/$(uname -r)/build ]]; then
      echo "Headers for the running kernel are missing: sudo apt install linux-headers-$(uname -r)"
      exit 1
    fi

    remove_dkms
    mkdir -p "/usr/src/$NAME-$VER"
    cp "$SRC"/module/{elan06fa_400khz.c,Makefile,dkms.conf} "/usr/src/$NAME-$VER/"
    dkms add -m "$NAME" -v "$VER" >/dev/null
    for k in /lib/modules/*; do
      k=$(basename "$k")
      [[ -d /lib/modules/$k/build ]] || continue
      echo "Building for kernel $k..."
      dkms install -m "$NAME" -v "$VER" -k "$k" >/dev/null || echo "  build failed for $k"
    done

    install -m 755 "$SRC/system/elan06fa-400khz-rescan" /usr/local/sbin/
    install -m 644 "$SRC/system/elan06fa-400khz.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable elan06fa-400khz.service >/dev/null

    echo
    dkms status -m "$NAME"
    check_secure_boot
    echo "Installed $NAME $VER. Reboot (a normal, warm reboot) to test it."
    ;;
  uninstall)
    systemctl disable elan06fa-400khz.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/elan06fa-400khz.service /usr/local/sbin/elan06fa-400khz-rescan
    systemctl daemon-reload
    modprobe -r elan06fa_400khz 2>/dev/null || true
    remove_dkms
    echo "Removed $NAME. The touchpad is back to the stock kernel behaviour after the next boot."
    ;;
  *)
    echo "Usage: sudo $0 [install|uninstall]"
    exit 1
    ;;
esac
