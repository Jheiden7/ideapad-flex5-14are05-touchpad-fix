# IdeaPad Flex 5 14ARE05: touchpad dead after every reboot on Linux (ELAN06FA)

**English** | [Español](README.es.md)

On recent Linux kernels the ELAN06FA touchpad of the **Lenovo IdeaPad Flex 5
14ARE05** stops working after a normal reboot, and only comes back once the
laptop has been left without power for a while.

This repository explains why and ships a small fix that works with **Secure
Boot enabled**.

> **Terms used here.** A **warm boot** is a reboot, or a short power-off with
> the charger connected: the touchpad keeps power and is not really reset. A
> **cold boot** is a power-on after the touchpad really lost power: the laptop
> was off with the charger unplugged, or off for hours.

## Symptoms

- After a cold boot the touchpad works; after a warm boot it is gone. It is not
  listed by `libinput list-devices` or `xinput`, and there is no error message.
- The touchscreen and pen keep working.
- On an affected kernel this line appears in the kernel log of **every** boot;
  it is the change that triggers the problem, not a sign that this boot failed:

  ```
  i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
  ```

  What tells a broken boot apart is that no `ELAN06FA:00 04F3:3140 Touchpad`
  input device appears afterwards.

## Cause

Kernel commit [`bfd74cd1fbc0`](https://git.kernel.org/torvalds/c/bfd74cd1fbc0)
("i2c: Force ELAN06FA touchpad I2C bus freq to 100KHz", Linux 6.14) forces every
ELAN06FA touchpad to a 100 kHz I2C bus, to fix "excessive smoothing" seen at
400 kHz on other laptops (e.g. the Lenovo V15 G4). Some distributions backported
it to older kernels too (Ubuntu's 6.8.0-142 kernel has it).

The Flex 5 14ARE05 firmware asks for **400 kHz**, which according to that commit
is also what the touchpad works with on Windows. On this laptop, after a warm
boot the touchpad stops answering reliably at 100 kHz, so the driver gives up
silently. At 400 kHz it worked in every warm reboot tested so far, and switching
the bus to 400 kHz even revives a touchpad that is already stuck.

The full investigation, with the measurements and everything that was ruled out,
is in [docs/DIAGNOSIS.md](docs/DIAGNOSIS.md).

## Tested on

| | |
|---|---|
| Laptop | Lenovo IdeaPad Flex 5 14ARE05 (81X2), Ryzen 5 4500U |
| BIOS / EC | EECN44WW (2023-09-04) / EEEC21WW |
| Touchpad | ELAN06FA (04F3:3140) on I2C controller AMDI0010:03, address 0x15 |
| OS | Linux Mint 22.3 (Ubuntu 24.04 base), kernel 7.0 HWE, Secure Boot on |

Only tested on the Debian/Ubuntu family (the scripts suggest `apt` commands).
Other distributions need DKMS and the kernel headers and are untested.

Results so far: 6 warm reboots at 400 kHz, all with a working touchpad (2 with a
mainline 6.13 kernel that predates the quirk, 4 with the fix). Version 1.0 was
used for 18 days: of 24 boots, 21 were cold boots where the touchpad already
worked and 3 were warm reboots, each recovered on the first attempt. Version 1.1
was verified with a warm reboot. Version 1.2, which moves the touchpad to
400 kHz in every boot, is **pending verification**. At 400 kHz the touchpad
feels normal (no smoothing or lag). The sample is still small: reports are
welcome.

## Am I affected?

Run this **right after a warm boot** (a normal reboot with the charger
connected), before installing anything:

```bash
./tools/check.sh
```

It only reads system information (no root needed). On an affected laptop
without the fix it ends like this:

```
Touchpad
  [ok]   ELAN06FA touchpad present in ACPI
  [--]   attached to I2C controller AMDI0010:03
  [!!]   the kernel forces this bus to 100 kHz (the quirk behind the problem)
  [!!]   touchpad is NOT bound to a driver (not working in this boot)
...
Verdict: affected (bus forced to 100 kHz, touchpad not probed); the fix is not installed.
```

You are affected if the touchpad is present, the bus is forced to 100 kHz and
the touchpad is **not bound** after a warm boot. After a cold boot the touchpad
works, so a single cold boot proves nothing.

In that broken state you can also watch the touchpad fail to answer on the bus
(needs `i2c-tools`):

```bash
sudo ./tools/ack-test.sh
```

A stuck touchpad answers only some of the reads, or none. For reference, a
healthy one answered 20/20 when its driver was unbound by hand (see
[docs/DIAGNOSIS.md](docs/DIAGNOSIS.md)).

## Install

Requirements: `dkms` and the kernel headers (`linux-headers-$(uname -r)`).

1. Clone the repository and run the installer:

   ```bash
   git clone https://github.com/Jheiden7/ideapad-flex5-14are05-touchpad-fix.git
   cd ideapad-flex5-14are05-touchpad-fix
   sudo ./install.sh
   ```

2. If the installer printed a **Secure Boot warning**, enroll the signing key
   first (see below); otherwise the kernel will refuse the module.
3. Reboot normally and run `./tools/check.sh`. It should end with
   `Verdict: affected, and the fix is working (touchpad at 400 kHz).`

### Secure Boot

DKMS signs the module with the machine's MOK key, which has to be enrolled once.
The installer tells you whether it is and prints its path: on Ubuntu and Linux
Mint it is `/var/lib/shim-signed/mok/MOK.der`, with upstream DKMS
`/var/lib/dkms/mok.pub`. To enroll it, use the path the installer printed:

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
```

Choose a one-time password, using only lowercase letters and digits, since the
next screen uses a US keyboard layout. Reboot: a blue *MOK management* screen
appears. **Press a key within 10 seconds** (or it is skipped), then pick
**Enroll MOK → Continue → Yes**, type the password and reboot.

## How it works

1. A tiny kernel module puts a kretprobe on `i2c_acpi_find_bus_speed()`. When
   the kernel asks for the bus speed of the touchpad's I2C controller (found
   through the touchpad's ACPI parent) and gets 100 kHz, the module returns
   400 kHz instead. Other buses are not touched, and the module only loads on
   the tested model. On this model the firmware asks for 400 kHz, so a 100 kHz
   answer can only come from the quirk.
2. The I2C controller driver is built into the kernel and probes before any
   module can load. The module has no hardware alias either, so the boot
   service `elan06fa-400khz.service` is what loads it, in every boot. Then, if
   this kernel forced the bus to 100 kHz, the service rebinds the controller so
   the touchpad probes again at 400 kHz:
   - after a warm boot this recovers the touchpad;
   - after a cold boot the touchpad already works, and is moved to 400 kHz
     (it disappears for about a second, before the login screen);
   - if a touchpad that worked at 100 kHz does not come back at 400 kHz, the
     service reverts the bus to 100 kHz;
   - on a kernel that does not force 100 kHz, it does nothing.
3. DKMS rebuilds and signs the module for every new kernel, as long as its
   headers are installed.

## Update and uninstall

The installer puts the module source in `/usr/src/elan06fa-400khz-<version>`,
builds the module through DKMS for every kernel that has its headers installed,
and installs `/usr/local/sbin/elan06fa-400khz-rescan` and
`/etc/systemd/system/elan06fa-400khz.service`. Keep the cloned repository: it is
needed to update or uninstall.

Update to a newer version:

```bash
git pull && sudo ./install.sh
```

Uninstall:

```bash
sudo ./install.sh uninstall
```

This removes everything listed above. Two things stay: the
`/etc/modprobe.d/elan06fa-400khz.conf` file, if you created one for `force=1`
(delete it by hand), and the enrolled MOK key, which is harmless and is also
used by any other DKMS module.

## FAQ

**Kernel updates?** DKMS rebuilds the module automatically. Check that
`dkms status elan06fa-400khz` lists the new kernel. If it does not, install that
kernel's `linux-headers` package and run `sudo ./install.sh` again.

**What if a future kernel changes?** If the module fails to build or load, the
service shows up in `systemctl --failed` with the message `Could not load
elan06fa_400khz…`, and the touchpad behaves as without the fix: it works after a
cold boot. If a kernel stops forcing 100 kHz, the service notices and does
nothing.

**Another laptop with an ELAN06FA touchpad?** Untested. First check that
`tools/check.sh`, run after a warm boot, shows the bus forced to 100 kHz and the
touchpad not bound. Note that the module raises any 100 kHz on the touchpad's
bus to 400 kHz, even if the firmware itself asked for 100 kHz: check the speed
in your DSDT's `I2cSerialBusV2` entry for the touchpad first (`acpidump`,
`iasl`). To try it at your own risk, add `options elan06fa_400khz force=1` to
`/etc/modprobe.d/elan06fa-400khz.conf`. The scripts expect the touchpad as
`i2c-ELAN06FA:00`, and `tools/ack-test.sh` uses address 0x15 unless you pass
`ADDR=0x..`. Please open an issue with the result.

**"loading out-of-tree module taints kernel" in the log?** Expected: the module
is not part of the official kernel. It is harmless.

**Why not just remove the quirk?** That needs a rebuilt kernel. The proper fix is
upstream: exempt this model from `i2c_acpi_force_100khz_device_ids`, or find the
real root cause (the original commit suspects the default I2C timing values
used when the firmware does not provide them).

## Upstream status

Not reported yet. A draft kernel patch that exempts this model from the 100 kHz
override is in [upstream/](upstream/README.md). It compiles but has not been
booted in a full kernel yet. Once something like it is merged, the module is no
longer needed. If you are affected, a report to the
[linux-i2c mailing list](https://lore.kernel.org/linux-i2c/) referencing this
repository would help.

## License

[GPL-2.0](LICENSE), the license required for Linux kernel modules.

Diagnosis and fix by Jheiden7, developed with the help of Claude (Anthropic).
