echo "Turn on USB4 and Thunderbolt on the N1x"

# See install/hardware/n1x.sh: linux-omarchy-n1x drives the USB4 host routers
# only when the USB4 resources stay powered, and docks need bus numbers set
# aside below the unconfigured tunnel root ports.
dropin=/etc/limine-entry-tool.d/00-omarchy-n1x-usb4.conf

if ! omarchy-hw-n1x || [[ -f $dropin ]]; then
  exit 0
fi

sudo install -Dm644 /dev/stdin "$dropin" <<'CONF'
# N1x: keep USB4 powered for the Thunderbolt connection manager, and leave bus
# numbers for docks. See install/hardware/n1x.sh.
KERNEL_CMDLINE[default]+=" power_wrap_drv.usb4_release=0 pci=hpbussize=0x20"
CONF

sudo limine-mkinitcpio
