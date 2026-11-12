#!/usr/bin/env bash
# Test denden-install end to end in a QEMU VM (KVM, UEFI), without touching
# any real disk:
#
#   scripts/test-install.sh install  # boot the newest ISO in out/, run the
#                                    # installer unattended on a blank 64 GB
#                                    # virtual disk, power off
#   scripts/test-install.sh boot     # boot the installed disk and save a
#                                    # screenshot of the desktop
#   scripts/test-install.sh          # both
#
# The install runs this checkout's packages/denden-installer/denden-install
# rather than the ISO's copy, so installer changes don't need an ISO rebuild.
# Downloaded packages are kept in a cache shared with the VM, so only the
# first run downloads the full ~2 GiB.
#
# Needs qemu-base, qemu-hw-display-virtio-vga, edk2-ovmf, python and socat.
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
  -nic user,model=virtio-net-pci
  -display none
)

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
  cp "${ovmf}/OVMF_VARS.4m.fd" "${vm}/vars.fd"
  bsdtar -xf "${iso}" -C "${vm}/boot" --strip-components 3 \
    arch/boot/x86_64/vmlinuz-linux-cachyos arch/boot/x86_64/initramfs-linux-cachyos.img

  # Run by the live system on tty1 (see archiso/airootfs/root/.automated_script.sh).
  cat > "${vm}/http/auto.sh" <<EOF
#!/bin/bash
exec > >(tee /dev/ttyS0) 2>&1
systemctl is-system-running --wait >/dev/null || true
mount -t 9p -o trans=virtio,version=9p2000.L,msize=1048576 pkgcache /var/cache/pacman/pkg
curl -fsS -o /tmp/denden-install http://10.0.2.2:${port}/denden-install
if DENDEN_PASSWORD=denden bash /tmp/denden-install --disk /dev/vda --hostname denden-vm \\
    --user tester --timezone Africa/Johannesburg --host-cache --yes; then
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

boot_phase() {
  [[ -f ${vm}/disk.qcow2 ]] || { echo "error: nothing installed; run the install phase" >&2; exit 1; }
  echo "==> Booting the installed disk; screenshot in ${boot_wait}s"
  rm -f -- "${vm}/qmp.sock" "${vm}/desktop.png"
  "${qemu_common[@]}" -device virtio-vga -qmp "unix:${vm}/qmp.sock,server,nowait" \
    -serial "file:${vm}/boot.log" &
  local qemu_pid=$!
  sleep "${boot_wait}"
  qmp "{\"execute\":\"screendump\",\"arguments\":{\"filename\":\"${vm}/desktop.png\",\"format\":\"png\"}}"
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

case "${1:-all}" in
  install) install_phase ;;
  boot) boot_phase ;;
  all) install_phase; boot_phase ;;
  *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
