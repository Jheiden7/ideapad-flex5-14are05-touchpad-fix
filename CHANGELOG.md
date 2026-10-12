# Changelog

## Unreleased

- CI (GitHub Actions): shellcheck on the scripts, and the module built against
  the Ubuntu 24.04 GA (6.8) and HWE kernel headers.
- Issue form for test reports from other machines.
- shellcheck cleanups in the scripts, with no change in behaviour.

## 1.2 — 2026-10-12

Verified on the IdeaPad Flex 5 14ARE05 (kernel 7.0.0-14-generic, Secure Boot on)
after a warm reboot (touchpad recovered) and a cold boot (working touchpad moved
to 400 kHz), in both cases without delaying the login screen.

- The boot service moves the touchpad to 400 kHz in every boot, also after a
  cold boot when it already works at 100 kHz, instead of acting only when the
  touchpad is missing. It does nothing on kernels that do not force 100 kHz,
  and reverts to 100 kHz if a working touchpad does not come back at 400 kHz.
- The login screen no longer waits for the service (the touchpad is
  hot-plugged), and the kernel log check reads `dmesg` first, using the slower
  journal only as a fallback.
- `tools/check.sh`: checks for the tested model, no longer flags the 100 kHz
  message as a problem when the fix switched the bus, and ends with a verdict.
- Documentation rewritten after an independent review: defines cold and warm
  boots, aligns the charger pattern with the diagnosis, explains that the
  service loads the module in every boot, how to read `check.sh`, the `force=1`
  caveat, updating and uninstalling, and tones down claims to what was measured.

## 1.1 — 2026-10-12

Verified on the IdeaPad Flex 5 14ARE05 (BIOS EECN44WW, kernel 7.0.0-14-generic,
Secure Boot on): touchpad recovered on the first attempt after a warm reboot.

- Find the touchpad's I2C controller through the ELAN06FA ACPI device instead of
  the hard-coded name `AMDI0010:03`, in the module and in the boot service.
- New module parameter `force=1` to load on untested models (experimental).
- `install.sh`: checks for DKMS, kernel headers and the Secure Boot (MOK) key
  (read from the DKMS configuration), builds the new version before removing
  older ones, keeps the old version if the build fails, and shows the build log
  on errors.
- Boot service: waits for the touchpad driver to finish its boot-time probe
  before deciding it failed, detects the touchpad through any driver, and fails
  visibly when the module cannot be loaded.
- Diagnostic tools: `tools/check.sh` (read-only, warns when the module is
  installed but not loaded) and `tools/ack-test.sh`.
- `upstream/`: draft kernel patch that exempts this model from the 100 kHz
  override.

## 1.0 — 2026-09-24

- First working version, tested on a Lenovo IdeaPad Flex 5 14ARE05 with BIOS
  EECN44WW and kernel 7.0.0-14-generic.
