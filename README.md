# IdeaPad Flex 5 14ARE05: touchpad dead after every reboot on Linux (ELAN06FA)

**English** | [Español](README.es.md)

On recent Linux kernels the ELAN06FA touchpad of the **Lenovo IdeaPad Flex 5
14ARE05** only works after the laptop is powered on with the charger unplugged.
After any normal reboot — or a power-off with the charger connected — the
touchpad is simply gone until all power is removed again.

This repository explains why and ships a small fix that works with **Secure
Boot enabled**.

## Symptoms

- The touchpad works after a cold boot without the charger, and disappears after
  a reboot. It is not listed by `libinput list-devices` or `xinput`, and there is
  no error message.
- The touchscreen and pen keep working.
- The kernel log of a broken boot contains this line, and no
  `ELAN06FA:00 04F3:3140 Touchpad` input device afterwards:

  ```
  i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
  ```

## Cause

Kernel commit [`bfd74cd1fbc0`](https://git.kernel.org/torvalds/c/bfd74cd1fbc0)
("i2c: Force ELAN06FA touchpad I2C bus freq to 100KHz", Linux 6.14) forces every
ELAN06FA touchpad to a 100 kHz I2C bus, to fix "excessive smoothing" seen at
400 kHz on other laptops (e.g. the Lenovo V15 G4). Some distributions backported
it to older kernels too (Ubuntu's 6.8 kernel has it).

The Flex 5 14ARE05 firmware asks for **400 kHz**, the speed Windows uses. On this
laptop, after a warm reset the touchpad stops answering reliably at 100 kHz,
so the driver gives up silently. At 400 kHz it works after every reboot, and
switching the bus to 400 kHz even revives a touchpad that is already stuck.

The full investigation, with the measurements and everything that was ruled out,
is in [docs/DIAGNOSIS.md](docs/DIAGNOSIS.md).

## Tested on

| | |
|---|---|
| Laptop | Lenovo IdeaPad Flex 5 14ARE05 (81X2), Ryzen 5 4500U |
| BIOS / EC | EECN44WW (2023-09-04) / EEEC21WW |
| Touchpad | ELAN06FA (04F3:3140) on I2C controller AMDI0010:03, address 0x15 |
| OS | Linux Mint 22.3 (Ubuntu 24.04 base), kernel 7.0 HWE, Secure Boot on |

Real use over 18 days with version 1.0: 24 boots, 3 of them warm reboots; the
touchpad was recovered on the first attempt every time, with no failures. At
400 kHz the touchpad feels normal (no smoothing or lag). Version 1.1 uses the
same mechanism and only changes how the touchpad's controller is found and how
failures are reported; its verification on the same laptop is **pending**. The
sample of warm reboots is still small: reports are welcome.

## Am I affected?

```bash
./tools/check.sh
```

It only reads system information (no root needed) and tells you whether the
ELAN06FA touchpad is present, whether its bus is forced to 100 kHz, whether it
probed in this boot and whether the fix is active.

With the touchpad broken you can also watch it fail to answer on the bus
(needs `i2c-tools`):

```bash
sudo ./tools/ack-test.sh
```

A healthy touchpad answers 20/20; a stuck one answers only some of the time, or
never.

## Install

Requirements: `dkms` and the kernel headers (`linux-headers-$(uname -r)`).

```bash
git clone https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix.git
cd ideapad-flex5-14are05-touchpad-fix
sudo ./install.sh
```

Then reboot normally and run `./tools/check.sh`. After a warm reboot it should
report `bus was switched to 400 kHz in this boot`, or check
`journalctl -b -u elan06fa-400khz`.

### Secure Boot

DKMS signs the module with the machine's MOK key. On Ubuntu and Linux Mint the
key already exists (`/var/lib/shim-signed/mok/MOK.der`) but has to be enrolled
once, or the kernel refuses the module. The installer warns you if it is not
enrolled. To enroll it:

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
```

Choose a one-time password, reboot, and in the blue *MOK management* screen pick
**Enroll MOK → Continue → Yes**, type the password and reboot. Press a key
within 10 seconds or the screen is skipped. Use a simple password (lowercase
letters and digits): that screen uses a US keyboard layout.

## How it works

1. A tiny kernel module puts a kretprobe on `i2c_acpi_find_bus_speed()`. When
   the kernel asks for the bus speed of the touchpad's I2C controller (found
   through the touchpad's ACPI parent) and gets the forced 100 kHz, the module
   returns 400 kHz instead. Other buses are not touched, and the module only
   loads on the tested model.
2. The I2C controller driver is built into the kernel and probes before any
   module can load, so a boot service (`elan06fa-400khz.service`) checks whether
   the touchpad was detected. If not, it rebinds the controller, which probes it
   again at 400 kHz. After a cold boot the touchpad already works and the service
   does nothing.
3. DKMS rebuilds and signs the module for every new kernel, as long as its
   headers are installed.

## Uninstall

```bash
sudo ./install.sh uninstall
```

## FAQ

**Kernel updates?** DKMS rebuilds the module automatically. Check with
`dkms status elan06fa-400khz`; install the matching `linux-headers` package if
the new kernel is missing.

**What if a future kernel changes?** If the probed function is renamed or the
module fails to build, it simply does not load and the touchpad falls back to
the stock behaviour (working after a cold boot). Nothing gets worse.

**Another laptop with an ELAN06FA touchpad?** Untested. If `tools/check.sh`
shows the same pattern you can try it at your own risk with
`options elan06fa_400khz force=1` in `/etc/modprobe.d/elan06fa-400khz.conf`, and
please open an issue with the result.

**"loading out-of-tree module taints kernel" in the log?** Expected: the module
is not part of the official kernel. It is harmless.

**Why not just remove the quirk?** That needs a rebuilt kernel. The proper fix is
upstream: exclude this model from `i2c_acpi_force_100khz_device_ids`, or find
the real root cause (the original commit suspects the default I2C timing values
used when the firmware does not provide them).

## Upstream status

Not reported yet. A draft kernel patch that exempts this model from the 100 kHz
override is in [upstream/](upstream/README.md); once something like it is
merged, the module is no longer needed. If you are affected, a report to the
[linux-i2c mailing list](https://lore.kernel.org/linux-i2c/) referencing this
repository would help.

## License

[GPL-2.0](LICENSE), the license required for Linux kernel modules.

Diagnosis and fix by Jheiden7, developed with the help of Claude (Anthropic).
