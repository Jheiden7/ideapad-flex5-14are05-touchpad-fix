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

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0 ${1:-install}"; exit 1; }

# DKMS versions of the module on the system, one per line. `dkms status`
# prints "name/ver, kernel, arch: state", or "name/ver: added" for a version
# that is not built for any kernel.
dkms_versions() {
  dkms status -m "$NAME" 2>/dev/null | sed -n "s|^$NAME/\([^,:]*\)[,:].*|\1|p" | sort -u
}

# Removes every DKMS version of the module except $1, if given.
remove_dkms() {
  local v
  for v in $(dkms_versions); do
    [[ $v == "${1:-}" ]] && continue
    dkms remove -m "$NAME" -v "$v" --all >/dev/null 2>&1 || true
    rm -rf "/usr/src/$NAME-$v"
  done
}

build_failed() {
  local log=/var/lib/dkms/$NAME/$VER/build/make.log
  echo "  Build failed for kernel $1."
  if [[ -f $log ]]; then
    echo "  Last lines of $log:"
    tail -n 15 "$log" | sed 's/^/    /'
  fi
}

# Certificate DKMS signs modules with: from its configuration, otherwise the
# usual locations (Ubuntu/Mint, then upstream DKMS).
dkms_mok_cert() {
  local c
  c=$(grep -hE '^[[:space:]]*mok_certificate=' /etc/dkms/framework.conf \
        /etc/dkms/framework.conf.d/*.conf 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d "\"'" || true)
  if [[ -z $c ]]; then
    for c in /var/lib/shim-signed/mok/MOK.der /var/lib/dkms/mok.pub; do
      [[ -f $c ]] && break
    done
  fi
  [[ -f $c ]] && echo "$c"
}

check_secure_boot() {
  command -v mokutil >/dev/null || return 0
  # mokutil's exit codes are not usable here (--test-key exits 1 for an
  # enrolled key), so match on its output instead of piping under pipefail.
  local state cert test
  state=$(mokutil --sb-state 2>&1 || true)
  [[ $state == *"SecureBoot enabled"* ]] || return 0
  cert=$(dkms_mok_cert || true)
  test=$([[ -n $cert ]] && mokutil --test-key "$cert" 2>&1 || true)
  if [[ -z $cert ]]; then
    echo "Secure Boot is enabled: make sure the key DKMS signs modules with is enrolled."
  elif [[ $test == *"already enrolled"* ]]; then
    echo "Secure Boot is enabled and the DKMS signing key ($cert) is enrolled."
  else
    cat <<EOF

WARNING: Secure Boot is enabled but the DKMS signing key ($cert) is not
enrolled, so the module will be refused at load time. Enroll it once:

    sudo mokutil --import $cert
    (choose a one-time password, reboot, then in the blue "MOK management"
     screen pick: Enroll MOK -> Continue -> Yes -> password -> Reboot)

EOF
  fi
}

case "${1:-install}" in
  install)
    command -v dkms >/dev/null || { echo "DKMS is missing: sudo apt install dkms"; exit 1; }
    KVER=$(uname -r)
    if [[ ! -d /lib/modules/$KVER/build ]]; then
      echo "Headers for the running kernel are missing: sudo apt install linux-headers-$KVER"
      exit 1
    fi

    # Build the new version first; older versions stay installed until it builds.
    dkms remove -m "$NAME" -v "$VER" --all >/dev/null 2>&1 || true
    rm -rf "/usr/src/$NAME-$VER"
    mkdir -p "/usr/src/$NAME-$VER"
    cp "$SRC"/module/{elan06fa_400khz.c,Makefile,dkms.conf} "/usr/src/$NAME-$VER/"
    dkms add -m "$NAME" -v "$VER" >/dev/null
    echo "Building for the running kernel $KVER..."
    if ! dkms build -m "$NAME" -v "$VER" -k "$KVER" >/dev/null 2>&1; then
      build_failed "$KVER"
      dkms remove -m "$NAME" -v "$VER" --all >/dev/null 2>&1 || true
      rm -rf "/usr/src/$NAME-$VER"
      echo "Nothing was changed: a previously installed version, if any, is still in place."
      exit 1
    fi

    remove_dkms "$VER"
    for k in /lib/modules/*; do
      k=$(basename "$k")
      [[ -d /lib/modules/$k/build ]] || continue
      echo "Installing for kernel $k..."
      dkms install -m "$NAME" -v "$VER" -k "$k" --force >/dev/null 2>&1 || build_failed "$k"
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
