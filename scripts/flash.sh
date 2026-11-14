#!/usr/bin/env bash
# Write a Den Den ISO to a USB stick from Linux; the counterpart of flash.ps1.
#
#   scripts/flash.sh out/denden-<date>-x86_64.iso /dev/sdX
#   scripts/flash.sh --erase ISO /dev/sdX   wipe the whole stick, backups too
#   scripts/flash.sh --yes ISO /dev/sdX     skip the typed confirmation
#   scripts/flash.sh ISO stick.img          write to a disk image file instead
#                                           (for testing this script)
#
# Find the stick with `lsblk -o NAME,MODEL,TRAN,SIZE`: by model and bus, not
# by name alone. The script writes the ISO byte for byte, then reads it back
# and compares SHA-256 hashes. It refuses anything that isn't a whole USB disk,
# and any disk with a mounted partition or active swap.
#
# A Den Den stick can also hold backups, in a partition named DENDEN_DATA
# after the image (`denden-backup setup` adds it). Flashing keeps that
# partition: only the image is rewritten. Then the image's partition table,
# which is sized to the image, is extended to the whole stick and the backup
# partition is put back with its number, type, GUIDs, name and attributes.
# The filesystem inside it is never written. --erase skips this, and the
# stick ends up holding only the new image.
#
# Needs util-linux (sfdisk, blkid, lsblk) and jq.
set -euo pipefail

data_name=DENDEN_DATA

die() { echo "flash.sh: $*" >&2; exit 1; }
usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

erase=0 yes=0 args=()
for arg in "$@"; do
  case ${arg} in
    --erase) erase=1 ;;
    --yes) yes=1 ;;
    -h|--help) usage ;;
    -*) die "unknown option ${arg}" ;;
    *) args+=("${arg}") ;;
  esac
done
((${#args[@]} == 2)) || usage
iso=${args[0]} target=${args[1]}

[[ -f ${iso} ]] || die "${iso}: no such ISO"
[[ -e ${target} ]] || die "${target}: no such disk or image file"

if [[ -b ${target} ]]; then
  mode=disk
  [[ ${EUID} -eq 0 ]] || exec sudo -- "$0" "$@"
  [[ $(lsblk -dno TYPE "${target}") == disk ]] \
    || die "${target} is a partition; give the whole disk, e.g. /dev/sdb"
  tran=$(lsblk -dno TRAN "${target}" | xargs)
  [[ ${tran} == usb ]] || die "${target} is ${tran:-not a USB disk}, not USB; refusing"
  if lsblk -nro MOUNTPOINTS "${target}" | grep -q .; then
    lsblk -o NAME,LABEL,MOUNTPOINTS "${target}" >&2
    die "${target} is in use (mounted, or swap); unmount it first"
  fi
  model=$(lsblk -dno MODEL "${target}" | xargs)
  sector=$(blockdev --getss "${target}")
  disk_size=$(blockdev --getsize64 "${target}")
  name="${target}  ${model:-unknown model}, USB"
else
  [[ -f ${target} ]] || die "${target} is neither a disk nor an image file"
  mode=image
  sector=512
  disk_size=$(stat -c %s -- "${target}")
  name="image ${target}"
fi

iso_size=$(stat -c %s -- "${iso}")
((iso_size <= disk_size)) || die "the ISO (${iso_size} bytes) is larger than the target (${disk_size} bytes)"
((iso_size % sector == 0)) || die "the ISO's size isn't a whole number of ${sector}-byte sectors"

gib() { awk -v b="$1" 'BEGIN { printf "%.2f GB", b / 1073741824 }'; }

# The backup partition to keep: found by name in the stick's current GPT.
# `sfdisk --dump` prints each partition as a line sfdisk reads back as-is.
keep='' keep_num='' keep_start=0 keep_size=0 keep_fs=''
table=$(sfdisk -J -- "${target}" 2>/dev/null || true)
if ((erase == 0)) && [[ -n ${table} ]] \
   && jq -e '.partitiontable.label == "gpt"' <<<"${table}" >/dev/null; then
  node=$(jq -r --arg n "${data_name}" \
    '.partitiontable.partitions[] | select(.name == $n) | .node' <<<"${table}" | head -n1)
  if [[ -n ${node} ]]; then
    keep_num=${node#"${target}"}
    keep_num=${keep_num#p}
    keep_start=$(jq -r --arg n "${node}" '.partitiontable.partitions[] | select(.node == $n) | .start' <<<"${table}")
    keep_size=$(jq -r --arg n "${node}" '.partitiontable.partitions[] | select(.node == $n) | .size' <<<"${table}")
    keep=$(sfdisk --dump -- "${target}" 2>/dev/null | grep -F "${node} :" | sed 's/^[^:]*: *//')
    [[ ${keep_num} =~ ^[0-9]+$ && -n ${keep} ]] || die "couldn't read the backup partition's entry"
    # The filesystem's own UUID (what denden-backup looks the partition up
    # by), to check afterwards that the partition still holds it.
    keep_fs=$(blkid -p -O $((keep_start * sector)) -o value -s UUID -- "${target}" 2>/dev/null || true)
    if ((keep_start * sector < iso_size)); then
      die "the new image ($(gib "${iso_size}")) would overwrite the backup partition, which starts at $(gib $((keep_start * sector))); use --erase to wipe the stick instead"
    fi
  fi
fi

echo "Target : ${name}  $(gib "${disk_size}")"
echo "Source : ${iso}  $(gib "${iso_size}")"
if [[ -n ${keep} ]]; then
  echo "Keeping: the backup partition ($(gib $((keep_size * sector))))"
  prompt="The Den Den image on the stick will be replaced; backups are kept. Type FLASH to continue: "
  word=FLASH
else
  prompt="Everything on the target will be destroyed. Type ERASE to continue: "
  word=ERASE
fi
if ((yes == 0)); then
  read -rp "${prompt}" answer || answer=
  [[ ${answer} == "${word}" ]] || { echo "Aborted."; exit 1; }
fi

echo "Hashing the ISO..."
iso_hash=$(sha256sum -- "${iso}" | cut -d' ' -f1)

echo "Writing..."
dd if="${iso}" of="${target}" bs=4M iflag=fullblock conv=fsync,notrunc status=progress

echo "Verifying..."
read_flags=count_bytes
if [[ ${mode} == disk ]]; then
  # Read the stick itself, not the page cache that the write just filled.
  blockdev --flushbufs "${target}"
  read_flags+=,direct
fi
disk_hash=$(dd if="${target}" bs=4M iflag="${read_flags}" count="${iso_size}" status=none | sha256sum | cut -d' ' -f1)
[[ ${disk_hash} == "${iso_hash}" ]] || die "verification FAILED: the target reads back ${disk_hash}, the ISO is ${iso_hash}"
echo "Verified SHA-256 ${iso_hash}"

# The image brought its own partition table, sized to the image. Move its
# backup copy to the end of the stick, which also makes the rest of the stick
# usable, and fixes the protective MBR's size; on a re-flash it overwrites the
# old table's backup copy too, so no stale table is left at the end.
if sfdisk -J -- "${target}" 2>/dev/null | jq -e '.partitiontable.label == "gpt"' >/dev/null; then
  if ! out=$(sfdisk --relocate gpt-bak-std -- "${target}" 2>&1); then
    echo "${out}" >&2
    die "couldn't extend the new partition table to the whole stick"
  fi
elif [[ -n ${keep} ]]; then
  die "the new image has no GPT, so the backup partition wasn't added back (its data is untouched at sector ${keep_start})"
fi

if [[ -n ${keep} ]]; then
  table=$(sfdisk -J -- "${target}")
  overlap=$(jq --argjson s "${keep_start}" \
    '[.partitiontable.partitions[] | select(.start + .size > $s)] | length' <<<"${table}")
  ((overlap == 0)) || die "a partition in the new image overlaps the backup partition; it wasn't added back"
  # Keep the partition's number if the new image left it free (it was 3 when
  # denden-backup added it); otherwise take the next free one.
  slot=(-N "${keep_num}")
  while read -r node; do
    num=${node#"${target}"}
    [[ ${num#p} == "${keep_num}" ]] && slot=(--append)
  done < <(jq -r '.partitiontable.partitions[].node' <<<"${table}")
  if ! out=$(echo "${keep}" | sfdisk --no-reread --no-tell-kernel "${slot[@]}" -- "${target}" 2>&1); then
    echo "${out}" >&2
    die "couldn't add the backup partition back; it starts at sector ${keep_start}, ${keep_size} sectors long, and its data is untouched"
  fi
  fs=$(blkid -p -O $((keep_start * sector)) -o value -s UUID -- "${target}" 2>/dev/null || true)
  [[ ${fs} == "${keep_fs}" ]] || die "the backup partition's filesystem changed (${keep_fs:-none} -> ${fs:-none})"
  echo "Backup partition kept."
fi

sfdisk --verify -- "${target}" >/dev/null 2>&1 || die "the new partition table doesn't verify: sfdisk --verify ${target}"

if [[ ${mode} == disk ]]; then
  blockdev --rereadpt "${target}" 2>/dev/null || partprobe "${target}" 2>/dev/null || true
  udevadm settle
fi
echo "Done."
