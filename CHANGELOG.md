# Changelog

## 1.1 — 2026-10-12

- Find the touchpad's I2C controller through the ELAN06FA ACPI device instead of
  the hard-coded name `AMDI0010:03`, in the module and in the boot service.
- New module parameter `force=1` to load on untested models (experimental).
- `install.sh`: checks for DKMS, kernel headers and the Secure Boot (MOK) key,
  and upgrades from earlier versions.
- Diagnostic tools: `tools/check.sh` (read-only) and `tools/ack-test.sh`.

## 1.0 — 2026-09-24

- First working version, tested on a Lenovo IdeaPad Flex 5 14ARE05 with BIOS
  EECN44WW and kernel 7.0.0-14-generic.
