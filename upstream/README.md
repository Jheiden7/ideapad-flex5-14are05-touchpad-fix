# Upstream patch (draft)

The module in this repository is a workaround. The real fix belongs in the
kernel: [`0001-i2c-acpi-Keep-400KHz-for-ELAN06FA-on-the-Lenovo-Idea.patch`](0001-i2c-acpi-Keep-400KHz-for-ELAN06FA-on-the-Lenovo-Idea.patch)
adds a DMI table to `drivers/i2c/i2c-core-acpi.c` so that the 100 kHz override
is not applied on the IdeaPad Flex 5 14ARE05. Once a kernel with it reaches your
distribution, the module is no longer needed.

## Status

**Draft, not submitted.** It applies to `drivers/i2c/i2c-core-acpi.c` as of
October 2026 and the patched file compiles, but it has not been built into a
full kernel and booted yet.

## Before sending it

1. Apply it to an up-to-date tree (`git am`), build a kernel with it and check
   on the laptop that the touchpad survives warm reboots **without** the module.
2. Replace the `From:` line with your real name (or known identity) and email,
   and add your `Signed-off-by:` (`git commit --amend -s`). The kernel does not
   accept anonymous contributions or `noreply` addresses.
3. Get the recipients from the tree itself:

   ```bash
   ./scripts/get_maintainer.pl 0001-*.patch
   ```

   It should list the I2C and ACPI maintainers and `linux-i2c@vger.kernel.org`;
   also Cc the author of commit `bfd74cd1fbc0`.
4. Send it as plain text with `git send-email` (see
   [Submitting patches](https://docs.kernel.org/process/submitting-patches.html)).
