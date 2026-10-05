echo "Apply the Dell XPS 13 Panther Lake display workaround"

if omarchy-hw-dell-xps13-dx13260-ptl; then
  source "$OMARCHY_PATH/install/hardware/dell-xps13-ptl-display.sh"

  # Record a successful machine-wide rebuild so other users do not repeat it.
  if [[ ! -e $display_rebuild_marker ]]; then
    if ! display_rebuild_output=$(sudo limine-mkinitcpio 2>&1); then
      printf '%s\n' "$display_rebuild_output" >&2
      exit 1
    fi
    printf '%s\n' "$display_rebuild_output"

    # Limine reports per-kernel build errors on stderr but can still exit zero.
    if [[ $display_rebuild_output == *"ERROR:"* ]]; then
      exit 1
    fi
    sudo install -Dm644 /dev/null "$display_rebuild_marker"
  fi

  if ! grep -Eq '(^| )xe.enable_psr2_sel_fetch=0( |$)' /proc/cmdline ||
    ! grep -Eq '(^| )xe.enable_panel_replay=0( |$)' /proc/cmdline; then
    omarchy-state set reboot-required
  fi
fi
