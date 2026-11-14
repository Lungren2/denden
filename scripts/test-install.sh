#!/usr/bin/env bash
# Test denden-install end to end in a QEMU VM (KVM, UEFI), without touching
# any real disk:
#
#   scripts/test-install.sh install  # boot the newest ISO in out/, run the
#                                    # installer unattended on a blank 64 GB
#                                    # virtual disk, power off
#   scripts/test-install.sh boot     # boot the installed disk, screenshot
#                                    # the start every 2 s and the desktop
#   scripts/test-install.sh windows  # boot, pick Windows in the startup
#                                    # picker and screenshot what starts
#   scripts/test-install.sh backup   # boot with a Den Den USB stick plugged
#                                    # in, set up backups on it, back up
#                                    # twice and check the backups
#   scripts/test-install.sh          # install, then boot
#
# A second, small disk stands in for a Windows disk: its EFI system partition
# holds a Limine labelled "Windows (simulated)" as EFI/Microsoft/Boot/
# bootmgfw.efi, so the startup picker should offer Windows and start it.
#
# The install runs this checkout's packages/denden-installer/denden-install
# and installs from this checkout's repo/ (scripts/build-packages.sh), not
# the ISO's copies, so changes to either don't need an ISO rebuild.
# Downloaded packages are kept in a cache shared with the VM, so only the
# first run downloads the full ~2 GiB.
#
# Needs qemu-base, qemu-hw-display-virtio-vga, edk2-ovmf, python, socat,
# limine, gptfdisk, dosfstools and mtools; `backup` also needs sudo (to put
# the test on the installed disk through qemu-nbd).
# The VM lives in ~/.cache/denden/vm; its serial logs and screenshots too.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
vm="${XDG_CACHE_HOME:-${HOME}/.cache}/denden/vm"
pkg_cache="${XDG_CACHE_HOME:-${HOME}/.cache}/denden/vm-pkgcache"
ovmf=/usr/share/edk2/x64
port=8123
boot_wait="${BOOT_WAIT:-150}"

qemu_common=(
  qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 4 -m 6G
  -drive "if=pflash,format=raw,readonly=on,file=${ovmf}/OVMF_CODE.4m.fd"
  -drive "if=pflash,format=raw,file=${vm}/vars.fd"
  -drive "file=${vm}/disk.qcow2,if=virtio,format=qcow2"
  -drive "file=${vm}/windows.raw,if=virtio,format=raw"
  -nic user,model=virtio-net-pci
  -display none
)

# A 64 MiB GPT disk whose EFI system partition looks like Windows' to the
# picker; "starting Windows" shows a Limine menu saying so.
make_windows_disk() {
  local esp="${vm}/windows-esp.img"
  truncate -s 64M "${vm}/windows.raw"
  sgdisk -n 1:2048:0 -t 1:ef00 -c 1:"EFI system partition" "${vm}/windows.raw" >/dev/null
  mkfs.fat -F 32 -n SYSTEM -C "${esp}" $(( (64 - 2) * 1024 - 1 )) >/dev/null
  mmd -i "${esp}" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot
  mcopy -i "${esp}" /usr/share/limine/BOOTX64.EFI ::/EFI/Microsoft/Boot/bootmgfw.efi
  printf 'timeout: no\ninterface_branding: Windows (simulated)\n\n/Windows started\n  protocol: efi\n  path: boot():/EFI/Microsoft/Boot/bootmgfw.efi\n' \
    | mcopy -i "${esp}" - ::/EFI/Microsoft/Boot/limine.conf
  dd if="${esp}" of="${vm}/windows.raw" bs=512 seek=2048 conv=notrunc status=none
  rm -- "${esp}"
}

install_phase() {
  local iso label
  iso="$(ls -t "${repo_root}"/out/denden-*.iso 2>/dev/null | head -n1)"
  [[ -n ${iso} ]] || { echo "error: no ISO in out/; run scripts/build.sh" >&2; exit 1; }
  label="$(blkid -o value -s LABEL "${iso}")"
  echo "==> Installing from ${iso} (${label})"

  rm -rf -- "${vm}"
  mkdir -p -- "${vm}/http" "${vm}/boot" "${pkg_cache}"
  cp "${repo_root}/packages/denden-installer/denden-install" "${vm}/http/"
  qemu-img create -q -f qcow2 "${vm}/disk.qcow2" 64G
  make_windows_disk
  cp "${ovmf}/OVMF_VARS.4m.fd" "${vm}/vars.fd"
  bsdtar -xf "${iso}" -C "${vm}/boot" --strip-components 3 \
    arch/boot/x86_64/vmlinuz-linux-cachyos arch/boot/x86_64/initramfs-linux-cachyos.img

  # Run by the live system on tty1 (see archiso/airootfs/root/.automated_script.sh).
  cat > "${vm}/http/auto.sh" <<EOF
#!/bin/bash
exec > >(tee /dev/ttyS0) 2>&1
systemctl is-system-running --wait >/dev/null || true
mount -t 9p -o trans=virtio,version=9p2000.L,msize=1048576 pkgcache /var/cache/pacman/pkg
mkdir -p /tmp/denden-repo
mount -t 9p -o trans=virtio,version=9p2000.L,msize=1048576,ro denden /tmp/denden-repo
curl -fsS -o /tmp/denden-install http://10.0.2.2:${port}/denden-install
if DENDEN_PASSWORD=denden bash /tmp/denden-install --disk /dev/vda --repo /tmp/denden-repo \\
    --hostname denden-vm --user tester --timezone Africa/Johannesburg --host-cache --yes; then
  echo "DENDEN-INSTALL: OK"
else
  echo "DENDEN-INSTALL: FAILED"
fi
sleep 2
poweroff
EOF
  python -m http.server --bind 127.0.0.1 --directory "${vm}/http" "${port}" >/dev/null 2>&1 &
  local http_pid=$!
  trap 'kill ${http_pid} 2>/dev/null || true' RETURN

  "${qemu_common[@]}" -no-reboot -cdrom "${iso}" \
    -virtfs "local,path=${pkg_cache},mount_tag=pkgcache,security_model=mapped-xattr" \
    -virtfs "local,path=${repo_root}/repo/x86_64,mount_tag=denden,security_model=none,readonly=on" \
    -kernel "${vm}/boot/vmlinuz-linux-cachyos" -initrd "${vm}/boot/initramfs-linux-cachyos.img" \
    -append "archisobasedir=arch archisolabel=${label} script=http://10.0.2.2:${port}/auto.sh console=ttyS0,115200" \
    -serial "file:${vm}/install.log"

  if grep -q 'DENDEN-INSTALL: OK' "${vm}/install.log"; then
    echo "==> Install succeeded (log: ${vm}/install.log)"
  else
    echo "==> Install FAILED; last lines of ${vm}/install.log:" >&2
    tail -n 40 "${vm}/install.log" >&2
    exit 1
  fi
}

qmp() { # qmp '{"execute": ...}'
  printf '%s\n%s\n' '{"execute":"qmp_capabilities"}' "$1" \
    | socat - "UNIX-CONNECT:${vm}/qmp.sock" >/dev/null
}

shot() { # shot NAME
  qmp "{\"execute\":\"screendump\",\"arguments\":{\"filename\":\"${vm}/$1.png\",\"format\":\"png\"}}"
}
key() { # key QCODE
  qmp "{\"execute\":\"send-key\",\"arguments\":{\"keys\":[{\"type\":\"qcode\",\"data\":\"$1\"}]}}"
}

boot_phase() {
  local pick=${1:-}
  [[ -f ${vm}/disk.qcow2 ]] || { echo "error: nothing installed; run the install phase" >&2; exit 1; }
  rm -rf -- "${vm}/qmp.sock" "${vm}/start" "${vm}/desktop.png" "${vm}/windows.png"
  mkdir -p -- "${vm}/start"
  "${qemu_common[@]}" -device virtio-vga -qmp "unix:${vm}/qmp.sock,server,nowait" \
    -serial "file:${vm}/boot.log" &
  local qemu_pid=$! t
  if [[ ${pick} == windows ]]; then
    echo "==> Booting the installed disk and picking Windows"
    sleep 6; shot start/picker
    key right; sleep 1; key ret; sleep 8; shot windows
    kill "${qemu_pid}"; wait "${qemu_pid}" 2>/dev/null || true
    echo "==> Screenshots: ${vm}/start/picker.png ${vm}/windows.png"
    return
  fi
  echo "==> Booting the installed disk; screenshots in ${vm}/start, desktop in ${boot_wait}s"
  for ((t = 2; t <= 40; t += 2)); do sleep 2; shot "start/$(printf %02d "${t}")s"; done
  sleep $((boot_wait > 40 ? boot_wait - 40 : 0))
  shot desktop
  # Shut down cleanly so the guest's journal reaches the disk; the logs are
  # how to check a session that a GPU-less VM can't display (niri skips
  # software rendering, so the screen stays on the console in a VM).
  qmp '{"execute":"system_powerdown"}' || true
  local i
  for ((i = 0; i < 60; i++)); do kill -0 "${qemu_pid}" 2>/dev/null || break; sleep 1; done
  kill "${qemu_pid}" 2>/dev/null || true
  wait "${qemu_pid}" 2>/dev/null || true
  echo "==> Screenshot: ${vm}/desktop.png"
}

# The installed disk's root and log subvolumes, through qemu-nbd: run CMD with
# them mounted at $1 (root) and $1/var/log.
with_installed_disk() { # with_installed_disk DIR CMD...
  local dir=$1; shift
  sudo modprobe nbd max_part=8
  sudo qemu-nbd -c /dev/nbd0 "${vm}/disk.qcow2"
  sudo udevadm settle
  sudo mkdir -p -- "${dir}"
  sudo mount -o subvol=@ /dev/nbd0p2 "${dir}"
  sudo mount -o subvol=@log /dev/nbd0p2 "${dir}/var/log"
  "$@" || true
  sudo umount -R "${dir}"
  sudo qemu-nbd -d /dev/nbd0 >/dev/null
}

backup_phase() {
  local iso mnt="${vm}/mnt" result
  [[ -f ${vm}/disk.qcow2 ]] || { echo "error: nothing installed; run the install phase" >&2; exit 1; }
  iso="$(ls -t "${repo_root}"/out/denden-*.iso 2>/dev/null | head -n1)"
  # A 16 GiB stick holding the image, as flash.ps1 leaves it.
  rm -f -- "${vm}/stick.raw"
  truncate -s 16G "${vm}/stick.raw"
  dd if="${iso}" of="${vm}/stick.raw" bs=4M conv=notrunc status=none

  # At the next boot, run the backup commands as root; their output goes to
  # the journal.
  write_test() {
    sudo tee "${mnt}/etc/systemd/system/denden-backup-test.service" >/dev/null <<'UNIT'
[Unit]
Description=Den Den backup test
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/bin/bash -xc 'denden-backup setup --yes && denden-backup && denden-backup status && echo "a change" > /home/tester/Documents/changed.txt && denden-backup && denden-backup restic snapshots && denden-backup restic ls latest /home/tester/Documents && echo DENDEN-BACKUP-TEST: OK'
UNIT
    sudo ln -sf ../denden-backup-test.service "${mnt}/etc/systemd/system/multi-user.target.wants/denden-backup-test.service"
  }
  with_installed_disk "${mnt}" write_test

  echo "==> Booting with a Den Den stick plugged in"
  rm -f -- "${vm}/qmp.sock"
  "${qemu_common[@]}" -device virtio-vga -qmp "unix:${vm}/qmp.sock,server,nowait" \
    -device qemu-xhci -drive "if=none,id=stick,format=raw,file=${vm}/stick.raw" \
    -device usb-storage,drive=stick -serial "file:${vm}/boot.log" &
  local qemu_pid=$!
  sleep "${boot_wait}"
  qmp '{"execute":"system_powerdown"}' || true
  local i
  for ((i = 0; i < 60; i++)); do kill -0 "${qemu_pid}" 2>/dev/null || break; sleep 1; done
  kill "${qemu_pid}" 2>/dev/null || true
  wait "${qemu_pid}" 2>/dev/null || true

  read_log() {
    sudo journalctl -D "${mnt}/var/log/journal" --no-pager -o cat \
      -u denden-backup-test.service -u denden-backup.service > "${vm}/backup.log"
    sudo rm -f "${mnt}/etc/systemd/system/denden-backup-test.service" \
      "${mnt}/etc/systemd/system/multi-user.target.wants/denden-backup-test.service"
  }
  with_installed_disk "${mnt}" read_log
  if grep -q '^DENDEN-BACKUP-TEST: OK' "${vm}/backup.log"; then
    echo "==> Backup test passed (log: ${vm}/backup.log)"
  else
    echo "==> Backup test FAILED; ${vm}/backup.log:" >&2
    tail -n 40 "${vm}/backup.log" >&2
    exit 1
  fi
}

case "${1:-all}" in
  install) install_phase ;;
  boot) boot_phase ;;
  windows) boot_phase windows ;;
  backup) backup_phase ;;
  all) install_phase; boot_phase ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
