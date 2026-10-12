# Diagnosis

**English** | [Español](DIAGNOSIS.es.md)

How the cause was found, what was measured, and what was ruled out on the way.
Hardware: Lenovo IdeaPad Flex 5 14ARE05 (81X2), BIOS EECN44WW, EC EEEC21WW,
Linux Mint 22.3 with kernel 7.0.0-14-generic, Secure Boot enabled.

## 1. The symptom pattern

The touchpad had worked on Windows across reboots. On Linux it worked only after
powering on with the charger unplugged. Cross-checking two weeks of boot logs
(how the previous boot ended, charger state at boot, whether the touchpad input
device appeared) confirmed it:

| Previous shutdown | Charger at boot | Touchpad |
|---|---|---|
| Reboot | connected | broken, every time |
| Short power-off (1–2 min) | connected | broken, almost every time |
| Long power-off (overnight) or power-off without charger | any | working, almost every time |

While the charger is connected the touchpad keeps power during a reboot or a
power-off, so it never really resets. Only removing all power brings it back.

## 2. What happens at boot

In a broken boot `i2c_hid_acpi` fails to probe the touchpad without logging
anything: its first read of the device's I2C address gets no acknowledge, so
probe returns `-ENXIO` (only printed at debug level). Rebinding the driver by
hand gives either `No such device or address`, or, when the device answers the
first read, `failed to fetch HID descriptor: -121`.

The device is `\_SB.I2CD.TPDD` in the DSDT, attached to the I2C controller
`AMDI0010:03`:

```
I2cSerialBusV2 (0x0015, ControllerInitiated, 0x00061A80, ...)   // address 0x15, 400 kHz
GpioInt (Level, ActiveLow, ExclusiveAndWake, PullUp, ...) { 0x0009 }
Method (_PS0, 0, NotSerialized) { }   // empty
Method (_PS3, 0, NotSerialized) { }   // empty
```

The DSDT asks for 400 kHz, but since Linux 6.14 the kernel overrides it:

```
i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
```

## 3. Measuring the bus

With the driver unbound, reading the touchpad's address 20 times (every 0.25 s,
`i2cget`) shows the difference clearly (`S` = acknowledged, `.` = no answer):

| Touchpad state | Answers |
|---|---|
| Healthy (after a cold boot) | `SSSSSSSSSSSSSSSSSSSS` (20/20) |
| After a warm reboot | `..S......S..S.....SS` (~25 %), sometimes `....................` |

The touchpad is alive (it even returned a valid HID descriptor, 04F3:3140, when
caught answering) but it only answers some of the time, so the many transfers
of a full probe never succeed.

## 4. Hypotheses ruled out

Everything below was tried on a stuck touchpad, without success:

| Hypothesis | Test | Result |
|---|---|---|
| Probe races at boot | Rebinding `i2c_hid_acpi`, many times, timed to moments when the device answered | still fails |
| I2C controller state | Unbinding and rebinding `i2c_designware` | still fails |
| Touchpad left in HID sleep | Sending HID `SET_POWER(ON)` and `RESET` by hand (`i2ctransfer`) | accepted, still answers only ~25 % |
| Caused by the shutdown `SLEEP` command | Unbinding the driver and leaving the touchpad awake right before a reboot | broken after the reboot anyway |
| Touchpad needs a power cycle | Toggling the touchpad off/on through the EC (`ideapad_laptop touchpad_ctrl_via_ec=1`) for 3 s and for 60 s | the touchpad stops answering while off (whether the EC cuts its power or only isolates it is unknown), still stuck afterwards |
| Controller needs a hardware reset | Calling the controller's ACPI `RSET` method (AOAC reset, never used by Linux) with `acpi_call` | runs fine (`0x0`), still stuck |
| Platform state | S3 suspend and resume | still stuck |
| Interrupt line without pull-up | GPIO 9 had its pull-up off in one broken boot; enabling it | pull-up was already on in other broken boots; no change |
| EC state | Dumping the 256 EC registers (`ec_sys`, read-only) in broken and healthy states | touchpad-related fields identical; only battery and thermal values differed |
| BIOS settings | Checking the setup menu (no Fast Boot option) | nothing relevant |
| Older kernel | Ubuntu's 6.8.0-142 kernel | also forces 100 kHz (backported quirk) |

Since resetting everything on the touchpad side changed nothing, the remaining
variable was the one thing Windows and Linux do differently: the bus speed.

## 5. The decisive test

Mainline 6.13 (kernel.ubuntu.com) predates the quirk, so it keeps the 400 kHz
from the DSDT. It is unsigned, so Secure Boot was disabled for this test. (The
DKMS key that Ubuntu creates is restricted to module signing, so it cannot sign
a kernel.) Four consecutive warm reboots with the charger connected:

| Kernel | Bus speed | Previous boot ended with | Touchpad |
|---|---|---|---|
| 6.13 | 400 kHz | reboot | working |
| 7.0 | 100 kHz | reboot | **broken** |
| 7.0 | 100 kHz | reboot | **broken** |
| 6.13 | 400 kHz | reboot (from the broken 7.0) | working |

At 400 kHz the touchpad survives every reboot, and the last row shows that
400 kHz also recovers a touchpad that was stuck at 100 kHz.

## 6. The fix

Since the touchpad can be recovered after the fact, there is no need for a
patched kernel: a module that changes the speed for this one bus, plus a rebind
of the controller after boot, is enough. See "How it works" in the
[README](../README.md).

With the fix (version 1.0) on 7.0.0-14 (Secure Boot on, module signed with the
MOK key):

```
i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
elan06fa_400khz: active for AMDI0010:03
i2c_designware AMDI0010:03: [Firmware Bug]: DSDT uses known not-working I2C bus speed 400000, forcing it to 100000
elan06fa_400khz: AMDI0010:03: bus speed 100 kHz -> 400 kHz
input: ELAN06FA:00 04F3:3140 Touchpad as /devices/platform/AMDI0010:03/i2c-4/i2c-ELAN06FA:00/...
```

In 18 days of normal use with version 1.0: 24 boots, 21 cold (touchpad already
working, service idle) and 3 warm reboots, all recovered on the first attempt.
Version 1.1 keeps the same mechanism; its verification is pending.

## 7. Open questions

- **Why does 100 kHz fail only after a warm reset?** Unknown. The original
  commit notes that the device works on Windows at 400 kHz and suspects the
  default high/low SCL counts (HCNT/LCNT) the designware driver computes when the
  DSDT does not provide them, which is the case here. It is also possible that
  the firmware talks to the touchpad at 400 kHz during a warm boot and leaves it
  in a state that does not cope with 100 kHz.
- **Does the "excessive smoothing" that motivated the quirk appear at 400 kHz on
  this model?** Not observed: the touchpad feels normal.
- **Other laptops with ELAN06FA?** Untested.
