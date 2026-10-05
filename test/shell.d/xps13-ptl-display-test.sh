#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/dell-xps13-ptl-display.sh"
migration="$ROOT/migrations/1790916392.sh"

grep -Fq 'run_logged "$OMARCHY_INSTALL/hardware/dell-xps13-ptl-display.sh"' "$ROOT/install/hardware/all.sh" ||
  fail "hardware setup applies the XPS 13 Panther Lake display workaround"
pass "hardware setup applies the XPS 13 Panther Lake display workaround"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export OMARCHY_PATH="$test_tmp/omarchy"
mkdir -p "$test_tmp/bin" "$OMARCHY_PATH/install/hardware"

# Redirect fixed production paths only in temporary source copies.
redirect_path() {
  local literal replacement
  printf -v literal '%q' "$2"
  replacement=$(printf '%s' "$literal" | sed 's/[\\&|]/\\&/g')
  sed "s|$1|$replacement|g"
}

display_conf="$test_tmp/limine/dell-xps13-ptl-display.conf"
rebuild_marker="$test_tmp/rebuilt"
running_cmdline="$test_tmp/cmdline"
redirect_path '"/etc/limine-entry-tool.d/dell-xps13-ptl-display.conf"' "$display_conf" <"$leaf" |
  redirect_path '"/var/lib/omarchy/migrations/1790916392"' "$rebuild_marker" |
  redirect_path '/etc/limine-entry-tool.d$' "$test_tmp/limine" >"$OMARCHY_PATH/install/hardware/${leaf##*/}"
redirect_path '/proc/cmdline' "$running_cmdline" <"$migration" >"$test_tmp/migration.sh"

cat >"$test_tmp/bin/omarchy-hw-match" <<'SH'
#!/bin/bash
[[ $TEST_MODEL == *"$1"* ]]
SH
cat >"$test_tmp/bin/omarchy-hw-intel-ptl" <<'SH'
#!/bin/bash
[[ $TEST_PTL == "1" ]]
SH
cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
exec "$@"
SH
cat >"$test_tmp/bin/limine-mkinitcpio" <<'SH'
#!/bin/bash
if [[ ${TEST_REBUILD_ERROR:-0} == "1" ]]; then
  printf '\033[31mERROR: mkinitcpio failed for kernel fixture, skipping.\033[0m\n' >&2
  exit 0
fi
declare -A KERNEL_CMDLINE=([default]="root=UUID=keep quiet")
source "$TEST_DISPLAY_CONF"
printf '%s\n' "${KERNEL_CMDLINE[default]}" >"$TEST_IMAGE_CMDLINE"
exit "${TEST_REBUILD_STATUS:-0}"
SH
cat >"$test_tmp/bin/omarchy-state" <<'SH'
#!/bin/bash
printf 'state %s\n' "$*" >>"$TEST_LOG"
SH
chmod +x "$test_tmp/bin/"*
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export TEST_LOG="$test_tmp/calls" TEST_MODEL="XPS 13 DX13260" TEST_PTL=1
export TEST_DISPLAY_CONF="$display_conf" TEST_IMAGE_CMDLINE="$test_tmp/image-cmdline"
printf '%s\n' 'root=UUID=keep quiet' >"$running_cmdline"

run_leaf() {
  : >"$TEST_LOG"
  bash -euo pipefail -c 'source "$1"' bash "$OMARCHY_PATH/install/hardware/${leaf##*/}"
}
run_migration() {
  : >"$TEST_LOG"
  bash -euo pipefail "$test_tmp/migration.sh" >/dev/null
}

TEST_MODEL="XPS 13 9340" run_leaf
[[ ! -e $display_conf && ! -s $TEST_LOG ]] || fail "other XPS models are unchanged"
TEST_PTL=0 run_leaf
[[ ! -e $display_conf && ! -s $TEST_LOG ]] || fail "DX13260 without Panther Lake is unchanged"
TEST_MODEL="ThinkPad X1" run_migration
[[ ! -e $display_conf && ! -e $rebuild_marker && ! -s $TEST_LOG ]] || fail "migration skips unrelated hardware"
pass "hardware setup and migration skip unrelated models and GPUs"

run_leaf
declare -A KERNEL_CMDLINE=([default]="root=UUID=keep quiet")
source "$display_conf"
expected_cmdline='root=UUID=keep quiet xe.enable_psr2_sel_fetch=0 xe.enable_panel_replay=0'
[[ ${KERNEL_CMDLINE[default]} == "$expected_cmdline" ]] || fail "drop-in adds both parameters and preserves the root command line"
pass "drop-in adds both parameters and preserves the root command line"

run_leaf
[[ ! -s $TEST_LOG ]] || fail "repeated hardware setup does not rewrite or duplicate parameters"
pass "repeated hardware setup does not rewrite or duplicate parameters"

TEST_REBUILD_STATUS=1 run_migration && fail "a failed boot rebuild leaves the migration pending"
[[ ! -e $rebuild_marker ]] && ! grep -q '^state ' "$TEST_LOG" ||
  fail "a failed boot rebuild creates no completion marker or reboot state"
pass "a failed boot rebuild leaves the migration pending without recording completion"

printf '%s\n' 'root=UUID=keep quiet' >"$TEST_IMAGE_CMDLINE"
TEST_REBUILD_ERROR=1 run_migration && fail "Limine's swallowed build error leaves the migration pending"
[[ ! -e $rebuild_marker && $(<"$TEST_IMAGE_CMDLINE") == 'root=UUID=keep quiet' ]] &&
  ! grep -q '^state ' "$TEST_LOG" || fail "a skipped boot image cannot record migration completion"
pass "Limine's swallowed build error leaves the migration pending with its old image"

run_migration
[[ -e $rebuild_marker && $(<"$TEST_IMAGE_CMDLINE") == "$expected_cmdline" ]] ||
  fail "retry rebuilds the boot image with both parameters before recording completion"
grep -q '^state set reboot-required$' "$TEST_LOG" || fail "the migration requests a reboot"
pass "retry rebuilds the boot image with both parameters and requests a reboot"

run_migration
[[ $(<"$TEST_LOG") == 'state set reboot-required' ]] ||
  fail "another user's migration skips the machine-wide rebuild and still requests reboot"
pass "another user's migration skips the machine-wide rebuild and still requests reboot"

printf '%s\n' 'root=UUID=keep quiet xe.enable_psr2_sel_fetch=0' >"$running_cmdline"
run_migration
[[ $(<"$TEST_LOG") == 'state set reboot-required' ]] || fail "one booted parameter is insufficient"
printf '%s\n' 'root=UUID=keep quiet xe.enable_panel_replay=0' >"$running_cmdline"
run_migration
[[ $(<"$TEST_LOG") == 'state set reboot-required' ]] || fail "the other booted parameter is insufficient"
printf '%s\n' "$expected_cmdline" >"$running_cmdline"
run_migration
[[ ! -s $TEST_LOG ]] || fail "both booted parameters avoid an unnecessary reboot prompt"
pass "the reboot prompt remains until both parameters are booted"

rm "$display_conf"
printf '%s\n' 'root=UUID=keep quiet' >"$TEST_IMAGE_CMDLINE"
printf '%s\n' 'root=UUID=keep quiet' >"$running_cmdline"
TEST_REBUILD_STATUS=1 run_migration && fail "a failed rebuild after restoring the drop-in leaves the migration pending"
[[ -e $display_conf && ! -e $rebuild_marker ]] && ! grep -q '^state ' "$TEST_LOG" ||
  fail "restoring the drop-in invalidates the old rebuild marker before a failed rebuild"
pass "restoring the drop-in invalidates the old marker before a failed rebuild"

run_migration
[[ -e $rebuild_marker && $(<"$TEST_IMAGE_CMDLINE") == "$expected_cmdline" ]] &&
  grep -q '^sudo limine-mkinitcpio$' "$TEST_LOG" &&
  grep -q '^state set reboot-required$' "$TEST_LOG" ||
  fail "restoring a lost drop-in rebuilds even after a previous successful migration"
pass "restoring a lost drop-in rebuilds even after a previous successful migration"
