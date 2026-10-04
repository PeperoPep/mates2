echo "Rebuild the N1x rescue boot entry after kernel updates"

# The N1x rescue entry is its own UKI, built once at install time. After a
# kernel update it still boots the old kernel, whose modules are gone. Install
# the pacman hook new installs get, and rebuild the entry for the kernel
# installed now.
if ! omarchy-hw-n1x || [[ ! -f /etc/limine-entry-tool.d/zz-omarchy-n1x-boot-order.conf ]]; then
  exit 0
fi

sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/zz-omarchy-n1x-rescue.hook <<'HOOK'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = linux-omarchy-n1x

[Action]
Description = Rebuilding the N1x rescue boot entry...
When = PostTransaction
Exec = /usr/bin/omarchy-refresh-n1x-rescue
HOOK

if pacman -Q linux-omarchy-n1x &>/dev/null; then
  sudo omarchy-refresh-n1x-rescue
fi
