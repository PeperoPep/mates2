# The Framework ALC285 exposes separate stereo "Speaker" and "Bass Speaker"
# mixers. Use software volume to preserve their relative levels, and initialize
# hardware levels after WirePlumber discovers the card on audio-session startup.
# https://github.com/NixOS/nixos-hardware/issues/1743

if omarchy-hw-framework16 && omarchy-hw-match '^Laptop 16 (AMD Ryzen AI 300 Series)$'; then
  config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
  mixer_source="$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
  mixer_target="$config_dir/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
  unit_name="omarchy-framework16-speaker-levels.service"
  unit_source="$OMARCHY_PATH/default/systemd/user/$unit_name"
  unit_target="$config_dir/systemd/user/$unit_name"
  first_install=true
  if [[ -e $unit_target || -L $unit_target ]]; then
    first_install=false
  fi

  # Verify existing configuration before installing a missing companion. Leave
  # custom or unavailable sources alone rather than assuming compatibility.
  if { [[ -e $mixer_target || -L $mixer_target ]] && ! cmp -s "$mixer_source" "$mixer_target"; } ||
    { [[ -e $unit_target || -L $unit_target ]] && ! cmp -s "$unit_source" "$unit_target"; }; then
    echo "Keeping custom Framework speaker configuration"
  else
    (
      set -e
      mkdir -p "$(dirname "$mixer_target")" "$config_dir/systemd/user/wireplumber.service.wants"
      mixer_staged=""
      unit_staged=""
      trap 'rm -f "$mixer_staged" "$unit_staged"' EXIT
      # Existing files and symlinks stay in place, even when they match defaults.
      if [[ ! -e $mixer_target && ! -L $mixer_target ]]; then
        mixer_staged=$(mktemp "$(dirname "$mixer_target")/.framework16-mixer.XXXXXX")
        cp --preserve=mode "$mixer_source" "$mixer_staged"
      fi
      if [[ $first_install == "true" ]]; then
        unit_staged=$(mktemp "$config_dir/systemd/user/.framework16-service.XXXXXX")
        cp --preserve=mode "$unit_source" "$unit_staged"
      fi
      if [[ -n $mixer_staged ]]; then
        mv -T "$mixer_staged" "$mixer_target"
      fi
      # Publish the complete unit only after its first enablement link exists.
      # An interruption leaves no unit, so a retry still finishes first setup.
      if [[ $first_install == "true" ]]; then
        ln -sfn "../$unit_name" "$config_dir/systemd/user/wireplumber.service.wants/$unit_name"
        mv -T "$unit_staged" "$unit_target"
      fi
    )
    # Enable offline too: fresh-install user setup can run without a user bus.
    # Apply on the next audio-session startup, without dropping audio connections
    # or increasing hardware gain before the software mixer has taken effect.
    if [[ $first_install == "true" ]]; then
      echo "Framework speaker volume fix enabled; reboot to apply"
    else
      echo "Framework speaker volume configuration ready; existing enablement preserved"
    fi
  fi
fi
