# qemu-user-static-binfmt registers its interpreters with flags FP. Docker
# buildx cross-arch builds run emulated-architecture containers where setuid
# binaries (e.g. sudo) need the C flag to keep their credentials under QEMU,
# and O so the interpreter works against a container whose rootfs differs
# from the host's. Add O and C to whatever flags the package's own
# registrations already carry -- never drop P, which keeps argv[0] as the
# original filename, or any other flag a later package update might add.
binfmt_source_dir="${OMARCHY_BINFMT_SOURCE_DIR:-/usr/lib/binfmt.d}"
binfmt_dir="${OMARCHY_BINFMT_DIR:-/etc/binfmt.d}"

mkdir -p "$binfmt_dir"
for conf in "$binfmt_source_dir"/qemu-*-static.conf; do
  [[ -e $conf ]] || continue

  line=$(<"$conf")
  flags=${line##*:}
  for flag in O C; do
    [[ $flags == *$flag* ]] || flags+=$flag
  done

  printf '%s:%s\n' "${line%:*}" "$flags" >"$binfmt_dir/$(basename "$conf")"
done
