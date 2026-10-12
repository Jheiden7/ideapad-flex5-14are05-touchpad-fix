// SPDX-License-Identifier: GPL-2.0
/*
 * elan06fa_400khz - run the ELAN06FA touchpad's I2C bus at 400 kHz again on
 * the Lenovo IdeaPad Flex 5 14ARE05.
 *
 * Since commit bfd74cd1fbc0 ("i2c: Force ELAN06FA touchpad I2C bus freq to
 * 100KHz", Linux 6.14, also backported to some distribution kernels) the
 * touchpad bus runs at 100 kHz. On this laptop the touchpad then stops
 * answering on the bus after every warm reboot (or power-off with the charger
 * connected) until all power is removed. At the 400 kHz the DSDT asks for --
 * the speed Windows uses -- it works across reboots, and switching to 400 kHz
 * also recovers a touchpad that is already stuck.
 *
 * A kretprobe on i2c_acpi_find_bus_speed() turns the forced 100 kHz back into
 * 400 kHz for the touchpad's I2C controller only. The controller driver is
 * built in and probes before modules load, so elan06fa-400khz.service rebinds
 * the controller afterwards.
 */
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/acpi.h>
#include <linux/device.h>
#include <linux/dmi.h>
#include <linux/i2c.h>
#include <linux/kprobes.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/ptrace.h>

static bool force;
module_param(force, bool, 0444);
MODULE_PARM_DESC(force, "Load on models that are not in the tested list (experimental)");

/* I2C controller the touchpad is attached to, looked up at load time. */
static struct device *touchpad_bus;

static int speed_entry(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct device *dev = (struct device *)regs_get_kernel_argument(regs, 0);

	*(bool *)ri->data = dev == touchpad_bus;
	return 0;
}

static int speed_return(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	if (*(bool *)ri->data &&
	    regs_return_value(regs) == I2C_MAX_STANDARD_MODE_FREQ) {
		regs_set_return_value(regs, I2C_MAX_FAST_MODE_FREQ);
		pr_info("%s: bus speed 100 kHz -> 400 kHz\n", dev_name(touchpad_bus));
	}
	return 0;
}

static struct kretprobe speed_probe = {
	.kp.symbol_name	= "i2c_acpi_find_bus_speed",
	.entry_handler	= speed_entry,
	.handler	= speed_return,
	.data_size	= sizeof(bool),
	.maxactive	= 4,
};

static const struct dmi_system_id tested_models[] = {
	{
		.ident = "Lenovo IdeaPad Flex 5 14ARE05",
		.matches = {
			DMI_MATCH(DMI_SYS_VENDOR, "LENOVO"),
			DMI_MATCH(DMI_PRODUCT_VERSION, "IdeaPad Flex 5 14ARE05"),
		},
	},
	{ }
};

/* The touchpad's ACPI parent is the I2C controller it hangs off. */
static struct device *find_touchpad_bus(void)
{
	struct acpi_device *touchpad, *parent;
	struct device *bus = NULL;

	touchpad = acpi_dev_get_first_match_dev("ELAN06FA", NULL, -1);
	if (!touchpad)
		return NULL;

	parent = acpi_dev_parent(touchpad);
	if (parent)
		bus = get_device(acpi_get_first_physical_node(parent));
	acpi_dev_put(touchpad);
	return bus;
}

static int __init elan06fa_400khz_init(void)
{
	int ret;

	if (!dmi_check_system(tested_models) && !force) {
		pr_info("untested model, not loading (force=1 overrides)\n");
		return -ENODEV;
	}

	touchpad_bus = find_touchpad_bus();
	if (!touchpad_bus) {
		pr_info("no ELAN06FA touchpad found\n");
		return -ENODEV;
	}

	ret = register_kretprobe(&speed_probe);
	if (ret) {
		pr_err("register_kretprobe failed: %d\n", ret);
		put_device(touchpad_bus);
		return ret;
	}

	pr_info("active for %s\n", dev_name(touchpad_bus));
	return 0;
}

static void __exit elan06fa_400khz_exit(void)
{
	unregister_kretprobe(&speed_probe);
	put_device(touchpad_bus);
}

module_init(elan06fa_400khz_init);
module_exit(elan06fa_400khz_exit);

MODULE_DESCRIPTION("Run the ELAN06FA touchpad I2C bus at 400 kHz on the IdeaPad Flex 5 14ARE05");
MODULE_LICENSE("GPL");
