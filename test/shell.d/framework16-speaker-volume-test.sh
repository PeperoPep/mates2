#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
export OMARCHY_PATH="$ROOT"
export XDG_CONFIG_HOME="$scratch/config"
export CALL_LOG="$scratch/calls"
export AUDIO_FIXTURE="$scratch/audio.json"
export PATH="$scratch/bin:$PATH"

cat > "$scratch/bin/omarchy-hw-framework16" <<'STUB'
#!/bin/bash
[[ ${TEST_VENDOR:-} == "Framework" && ${TEST_MODEL:-} == Laptop\ 16* ]]
STUB
cat > "$scratch/bin/omarchy-hw-match" <<'STUB'
#!/bin/bash
grep -qi -- "$1" <<< "${TEST_MODEL:-}"
STUB
cat > "$scratch/bin/pw-dump" <<'STUB'
#!/bin/bash
if [[ ${DELAY_DISCOVERY:-0} == "1" && ! -e $AUDIO_FIXTURE.ready ]]; then
  touch "$AUDIO_FIXTURE.ready"
  printf '[]\n'
else
  cat "$AUDIO_FIXTURE"
fi
STUB
cat > "$scratch/bin/amixer" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$CALL_LOG"
if [[ $3 == "sget" && $4 == "${MISSING_CONTROL:-}" ]]; then
  exit 1
fi
STUB
cat > "$scratch/bin/sleep" <<'STUB'
#!/bin/bash
true
STUB
cat > "$scratch/bin/cp" <<'STUB'
#!/bin/bash
destination=${@: -1}
if { [[ ${INTERRUPT_STAGE:-} == "partial-mixer" && $destination == */.framework16-mixer.* ]]; } ||
  { [[ ${INTERRUPT_STAGE:-} == "partial-unit" && $destination == */.framework16-service.* ]]; }; then
  printf '# interrupted copy\n' > "$destination"
  exit 99
fi
/usr/bin/cp "$@"
STUB
cat > "$scratch/bin/ln" <<'STUB'
#!/bin/bash
if [[ ${INTERRUPT_STAGE:-} == "before-enable" ]]; then
  exit 99
fi
/usr/bin/ln "$@"
STUB
cat > "$scratch/bin/mv" <<'STUB'
#!/bin/bash
destination=${@: -1}
if [[ $destination == */systemd/user/omarchy-framework16-speaker-levels.service ]]; then
  if [[ ${INTERRUPT_STAGE:-} == "before-publish" ]]; then
    exit 99
  fi
  /usr/bin/mv "$@" || exit $?
  if [[ ${INTERRUPT_STAGE:-} == "after-publish" ]]; then
    exit 99
  fi
else
  /usr/bin/mv "$@"
fi
STUB
chmod +x "$scratch/bin/"*
export TEST_VENDOR=Framework
export TEST_MODEL='Laptop 16 (AMD Ryzen AI 300 Series)'

setup_fix() {
  bash -euo pipefail "$ROOT/install/user/hardware/framework/fix-f16-ai300-speaker-volume.sh" >/dev/null
}
initialize_levels() {
  : > "$CALL_LOG"
  bash "$ROOT/bin/omarchy-hw-framework16-speaker-levels"
}
fixture() {
  cat > "$AUDIO_FIXTURE" <<JSON
[
  {"type":"PipeWire:Interface:Device","info":{"props":{
    "alsa.components":"HDA:1002aa01,00aa0100,00100900",
    "api.alsa.card":2,"api.alsa.soft-mixer":true}}},
  {"type":"PipeWire:Interface:Device","info":{"props":{
    "alsa.components":"$1","api.alsa.card":9,"api.alsa.soft-mixer":$2}}}
]
JSON
}

TEST_VENDOR=Other setup_fix
TEST_MODEL='Laptop 16 (AMD Ryzen 7040 Series)' setup_fix
[[ ! -e $XDG_CONFIG_HOME ]] || fail "setup leaves unsupported hardware alone"
pass "setup leaves unsupported hardware alone"

for stage in partial-mixer partial-unit before-enable before-publish after-publish; do
  interrupted_config="$scratch/interrupted-$stage"
  if XDG_CONFIG_HOME="$interrupted_config" INTERRUPT_STAGE="$stage" setup_fix; then
    fail "interruption at $stage must fail setup"
  fi
  interrupted_unit="$interrupted_config/systemd/user/omarchy-framework16-speaker-levels.service"
  interrupted_link="$interrupted_config/systemd/user/wireplumber.service.wants/omarchy-framework16-speaker-levels.service"
  if [[ -e $interrupted_unit && ! -e $interrupted_link ]]; then
    fail "interruption at $stage leaves a published unit without enablement"
  fi
  XDG_CONFIG_HOME="$interrupted_config" setup_fix
  cmp -s "$interrupted_unit" "$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service" || fail "retry at $stage installs the complete unit"
  cmp -s "$interrupted_config/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf" \
    "$ROOT/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf" || fail "retry at $stage installs the complete mixer rule"
  [[ -L $interrupted_link && -e $interrupted_link ]] || fail "retry at $stage enables initialization"
  pass "setup recovers from interruption at $stage"
done

# Preserve user-managed links even when their sources currently match defaults.
for linked_file in mixer unit; do
  for service_state in enabled disabled; do
    for entrypoint in setup migration; do
      linked_config="$scratch/linked-$linked_file-$service_state-$entrypoint"
      XDG_CONFIG_HOME="$linked_config" setup_fix
      linked_mixer="$linked_config/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
      linked_unit="$linked_config/systemd/user/omarchy-framework16-speaker-levels.service"
      linked_enablement="$linked_config/systemd/user/wireplumber.service.wants/omarchy-framework16-speaker-levels.service"
      if [[ $service_state == "disabled" ]]; then
        rm "$linked_enablement"
      fi
      if [[ $linked_file == "mixer" ]]; then
        linked_target="$linked_mixer"
        linked_source="$ROOT/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
      else
        linked_target="$linked_unit"
        linked_source="$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service"
      fi
      external_source="$scratch/external-$linked_file-$service_state-$entrypoint"
      cp "$linked_source" "$external_source"
      rm "$linked_target"
      ln -s "$external_source" "$linked_target"
      if [[ $entrypoint == "setup" ]]; then
        XDG_CONFIG_HOME="$linked_config" setup_fix
      else
        XDG_CONFIG_HOME="$linked_config" bash -euo pipefail "$ROOT/migrations/1791044739.sh" >/dev/null
      fi
      [[ -L $linked_target && $(readlink "$linked_target") == "$external_source" ]] || fail "$entrypoint preserves matching-content $linked_file symlink"
      cmp -s "$linked_source" "$external_source" || fail "$entrypoint leaves the external configuration source untouched"
      if [[ $service_state == "enabled" ]]; then
        [[ -L $linked_enablement && $(readlink "$linked_enablement") == ../omarchy-framework16-speaker-levels.service ]] || fail "$entrypoint preserves enabled state with a $linked_file symlink"
      else
        [[ ! -e $linked_enablement && ! -L $linked_enablement ]] || fail "$entrypoint preserves disabled state with a $linked_file symlink"
      fi
      printf '# edited external configuration\n' > "$external_source"
      [[ $(<"$linked_target") == '# edited external configuration' ]] || fail "external edits remain visible through the $linked_file symlink"
      pass "$entrypoint preserves $linked_file symlink, $service_state state, and external edits"
    done
  done
done

# Start with only one compatible symlink: fill the missing companion without
# taking ownership of the existing configuration or changing service state.
for linked_file in mixer unit; do
  for entrypoint in setup migration; do
    partial_config="$scratch/partial-$linked_file-$entrypoint"
    partial_mixer="$partial_config/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
    partial_unit="$partial_config/systemd/user/omarchy-framework16-speaker-levels.service"
    partial_enablement="$partial_config/systemd/user/wireplumber.service.wants/omarchy-framework16-speaker-levels.service"
    mkdir -p "$(dirname "$partial_mixer")" "$(dirname "$partial_unit")"
    if [[ $linked_file == "mixer" ]]; then
      partial_target="$partial_mixer"
      partial_source="$ROOT/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
      missing_target="$partial_unit"
      missing_source="$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service"
    else
      partial_target="$partial_unit"
      partial_source="$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service"
      missing_target="$partial_mixer"
      missing_source="$ROOT/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
    fi
    external_source="$scratch/partial-external-$linked_file-$entrypoint"
    cp "$partial_source" "$external_source"
    ln -s "$external_source" "$partial_target"
    if [[ $entrypoint == "setup" ]]; then
      XDG_CONFIG_HOME="$partial_config" setup_fix
    else
      XDG_CONFIG_HOME="$partial_config" bash -euo pipefail "$ROOT/migrations/1791044739.sh" >/dev/null
    fi
    [[ -L $partial_target && $(readlink "$partial_target") == "$external_source" ]] || fail "$entrypoint preserves the sole $linked_file symlink"
    cmp -s "$partial_source" "$external_source" || fail "$entrypoint preserves the external $linked_file source"
    cmp -s "$missing_target" "$missing_source" || fail "$entrypoint installs the missing companion for a $linked_file symlink"
    if [[ $linked_file == "mixer" ]]; then
      [[ -L $partial_enablement && -e $partial_enablement ]] || fail "$entrypoint enables the newly installed initializer"
    else
      [[ ! -e $partial_enablement && ! -L $partial_enablement ]] || fail "$entrypoint preserves the existing disabled unit symlink"
    fi
    XDG_CONFIG_HOME="$partial_config" setup_fix
    printf '# edited partial configuration\n' > "$external_source"
    [[ $(<"$partial_target") == '# edited partial configuration' ]] || fail "partial $linked_file source edits remain visible after repeat setup"
    pass "$entrypoint completes a sole $linked_file symlink while preserving its ownership and service state"
  done
done

# Unknown or unavailable linked configuration must not enable an initializer
# against an unverified mixer rule or service definition.
for linked_file in mixer unit; do
  for contents in custom dangling; do
    custom_config="$scratch/custom-only-$linked_file-$contents"
    custom_mixer="$custom_config/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
    custom_unit="$custom_config/systemd/user/omarchy-framework16-speaker-levels.service"
    mkdir -p "$(dirname "$custom_mixer")" "$(dirname "$custom_unit")"
    external_source="$scratch/custom-only-external-$linked_file-$contents"
    if [[ $contents == "custom" ]]; then
      printf '# user configuration\n' > "$external_source"
    fi
    if [[ $linked_file == "mixer" ]]; then
      custom_target="$custom_mixer"
      missing_target="$custom_unit"
    else
      custom_target="$custom_unit"
      missing_target="$custom_mixer"
    fi
    ln -s "$external_source" "$custom_target"
    XDG_CONFIG_HOME="$custom_config" setup_fix
    XDG_CONFIG_HOME="$custom_config" bash -euo pipefail "$ROOT/migrations/1791044739.sh" >/dev/null
    [[ -L $custom_target && $(readlink "$custom_target") == "$external_source" ]] || fail "custom $linked_file symlink is preserved"
    [[ ! -e $missing_target && ! -L $missing_target ]] || fail "unknown $linked_file configuration does not install a companion"
    [[ ! -L $custom_config/systemd/user/wireplumber.service.wants/omarchy-framework16-speaker-levels.service ]] || fail "unknown $linked_file configuration does not enable initialization"
    pass "setup and migration preserve a sole $contents $linked_file symlink without installing a companion"
  done
done

setup_fix
config="$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf"
unit="$XDG_CONFIG_HOME/systemd/user/omarchy-framework16-speaker-levels.service"
cmp -s "$config" "$ROOT/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf" || fail "mixer config is installed"
[[ -L $XDG_CONFIG_HOME/systemd/user/wireplumber.service.wants/omarchy-framework16-speaker-levels.service ]] || fail "startup initializer is enabled without a live user bus"
pass "setup installs the fix and enables initialization without a live user bus"

setup_fix
cmp -s "$unit" "$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service" || fail "repeated setup preserves service definition"
pass "setup is repeatable"

enablement="$XDG_CONFIG_HOME/systemd/user/wireplumber.service.wants/omarchy-framework16-speaker-levels.service"
rm "$enablement"
setup_fix
[[ ! -e $enablement && ! -L $enablement ]] || fail "disabled service stays disabled"
pass "disabled service stays disabled"

rm "$unit"
ln -s /dev/null "$unit"
setup_fix
[[ $(readlink "$unit") == /dev/null ]] || fail "masked service stays masked"
[[ ! -L $enablement ]] || fail "masked service is not enabled"
pass "masked service stays masked"
rm "$unit"
cp "$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service" "$unit"

# A dangling user symlink is also a replacement, not a fresh installation.
rm "$unit"
ln -s "$scratch/missing-unit" "$unit"
setup_fix
[[ $(readlink "$unit") == "$scratch/missing-unit" ]] || fail "dangling unit replacement is preserved"
[[ ! -L $enablement ]] || fail "dangling unit replacement is not enabled"
pass "dangling unit replacement is preserved"
rm "$unit"
cp "$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service" "$unit"

printf '# custom mixer rule\n' > "$config"
setup_fix
[[ $(<"$config") == '# custom mixer rule' ]] || fail "custom mixer config is preserved"
pass "custom mixer config is preserved"

cp "$ROOT/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf" "$config"
printf '# custom service\n' > "$unit"
setup_fix
[[ $(<"$unit") == '# custom service' ]] || fail "custom startup service is preserved"
pass "custom startup service is preserved"
cp "$ROOT/default/systemd/user/omarchy-framework16-speaker-levels.service" "$unit"

fixture 'HDA:10ec0285,f111000d,00100002' true
initialize_levels
expected=$'-c 9 sget Master\n-c 9 sget Speaker\n-c 9 sget Bass Speaker\n-c 9 sset Master 0dB unmute\n-c 9 sset Speaker 0dB unmute\n-c 9 sset Bass Speaker 0dB unmute'
[[ $(<"$CALL_LOG") == "$expected" ]] || fail "initializer targets the discovered Framework card only" "$(<"$CALL_LOG")"
pass "initializer sets only the discovered Framework card to 0 dB"

DELAY_DISCOVERY=1 initialize_levels
[[ $(<"$CALL_LOG") == "$expected" ]] || fail "initializer waits for delayed device discovery"
pass "initializer waits for delayed device discovery"

fixture 'HDA:10ec0285,f111000d,00100002' false
discovery_status=0
initialize_levels 2>/dev/null || discovery_status=$?
(( discovery_status == 75 )) || fail "discovery timeout requests a retry"
[[ ! -s $CALL_LOG ]] || fail "inactive software volume leaves hardware untouched"
pass "initializer refuses to raise levels without software volume"

fixture 'HDA:10ec0285,f111000d,00100002' true
initialize_levels
[[ $(<"$CALL_LOG") == "$expected" ]] || fail "initializer recovers after discovery timeout"
pass "initializer recovers after discovery timeout"

fixture 'HDA:10ec0285,12345678,00100002' true
if initialize_levels 2>/dev/null; then
  fail "initializer refuses a different codec subsystem"
fi
[[ ! -s $CALL_LOG ]] || fail "different codec subsystem leaves hardware untouched"
pass "initializer refuses a different codec subsystem"

fixture 'HDA:10ec0285,f111000d,00100002' true
control_status=0
MISSING_CONTROL='Bass Speaker' initialize_levels 2>/dev/null || control_status=$?
(( control_status != 0 && control_status != 75 )) || fail "missing controls fail without requesting discovery retry"
if grep -q ' sset ' "$CALL_LOG"; then
  fail "incomplete speaker controls must not cause a partial level change"
fi
pass "initializer checks every required control before changing levels"

TEST_VENDOR=Other initialize_levels
[[ ! -s $CALL_LOG ]] || fail "initializer leaves unsupported hardware alone"
pass "initializer leaves unsupported hardware alone"

# Existing installs use exactly the same setup path as fresh installs.
rm -f "$config"
bash -euo pipefail "$ROOT/migrations/1791044739.sh" >/dev/null
cmp -s "$config" "$ROOT/default/wireplumber/wireplumber.conf.d/framework16-ai300-soft-mixer.conf" || fail "migration installs the same fix"
pass "migration installs the same fix"
