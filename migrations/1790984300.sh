echo "Suspend the N1x to idle, since its firmware's deep sleep does not sleep"

# See install/hardware/n1x.sh: PSCI SYSTEM_SUSPEND returns at once on the N1x,
# so deep sleep (the kernel's default here) never sleeps and resume stalls.
dropin=/etc/limine-entry-tool.d/00-omarchy-n1x-sleep.conf

if ! omarchy-hw-n1x || [[ -f $dropin ]]; then
  exit 0
fi

sudo install -Dm644 /dev/stdin "$dropin" <<'CONF'
# N1x: the firmware's deep sleep does not sleep; suspend to idle instead. See
# install/hardware/n1x.sh.
KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle"
CONF

# The kernel parameter takes effect from the next boot; switch this boot now.
echo s2idle | sudo tee /sys/power/mem_sleep >/dev/null
sudo limine-mkinitcpio
