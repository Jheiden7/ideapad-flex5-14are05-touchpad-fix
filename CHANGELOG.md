# Changelog

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
