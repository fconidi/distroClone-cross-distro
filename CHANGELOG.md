# Changelog

## v1.3.7 — 2026-04-22

### Bug Fix

"Custom password" never applied — `ROOT_PASSWORD` set by the dialog was overwritten by a hardcoded `ROOT_PASSWORD="root"` assignment in section [4/30], executed after the dialog. Password always defaulted to `root` regardless of user input. Fixed by using `ROOT_PASSWORD="${ROOT_PASSWORD:-root}"` to preserve the value from the dialog.

---

## v1.3.6 — 2026-04-20

First public release of **DistroClone Cross-Distro** — a ground-up rewrite of the original
[DistroClone (Debian/Ubuntu)](https://github.com/fconidi/distroClone) to support multiple
distribution families from a single AppImage.

---

### Distributions Supported

| Distribution | btrfs | LUKS | Snapper |
|---|---|---|---|
| Arch Linux | ✓ | ✓ | — |
| CachyOS | ✓ | ✓ | ✓ grub-btrfs |
| EndeavourOS | ✓ | ✓ | — |
| Garuda Linux | ✓ | ✓ | ✓ firstboot |
| Manjaro | ✓ | ✓ | ✓ if installed |
| Fedora | ✓ | ✓ | — |
| openSUSE Tumbleweed | ✓ | ✓ | ✓ YaST + CLI |

---

### Architecture

- **Single AppImage** — no installation, no host dependencies to manage
- **`distro-detect.sh`** — unified distribution + feature detection (family, initramfs backend, kernel flavor, live stack) via `/etc/os-release` → `ID_LIKE` → sentinel file priority chain
- **`calamares-config.sh`** — generates the full Calamares module tree at ISO-build time, adapting every module to the detected family (~2200 lines)
- **Crypto layer** (`dc-crypto.sh` / `dc-initramfs.sh` / `dc-grub.sh`) — LUKS UUID detection at install time, mkinitcpio + dracut backends, BLS entry patching, btrfs rootflags injection
- **`dc-firstboot.service`** — systemd oneshot that runs on the installed clone's first boot: home directory creation, account unlock, snapper setup, grub-btrfs activation

---

### Bug Fixes

#### Arch Family (CachyOS, Garuda, EndeavourOS, Manjaro)

- **Filesystem detection**: `partitionLayout.filesystem` now derived from source `/` via `findmnt -no FSTYPE /` instead of hardcoded `ext4`. Fixes: CachyOS clone created ext4 target even when source was btrfs; Calamares dropdown was ignored.

- **CachyOS / Garuda GRUB boot fail after install**: GRUB btrfs driver 2.14 cannot navigate `subvol=@` when default subvolume is set to `@` (ID 256) — kernel path `/boot/vmlinuz` resolves to top-level, not inside `@`. Fixed by skipping `btrfs subvolume set-default @` on Garuda and CachyOS; default remains top-level ID 5. `dc-grub.sh` injects `/@/` prefix into grub.cfg `linux`/`initrd` lines when needed.

- **Garuda: "premature end of file" on kernel boot**: `rsync` (used by Calamares extract) creates kernel and initramfs files with sparse / multi-extent btrfs layout. Garuda's GRUB btrfs driver cannot read these files → `error: file '/@/boot/vmlinuz-linux-zen' not found`. Fixed by `dc_defrag_boot_files_btrfs()`: rewrites all `/boot/vmlinuz-*`, `/boot/initramfs-*.img`, `/boot/*-ucode.img` with `cp --sparse=never` + `btrfs filesystem defragment -r /boot/` before `grub-install`. No-op on non-btrfs targets.

- **Garuda dual-disk ESP collision**: cloning Garuda to a secondary disk (`/dev/sdb`) while the original is on `/dev/sda` overwrote the original's EFI entries and ESP directory. Fixed by:
  1. `bootloader-id` always suffixed with `Clone` (e.g. `GarudaClone`) — avoids `EFI/Garuda/` collision
  2. Global `blkid` ESP search removed — ESP resolved only from target disk
  3. `EFI/BOOT/BOOTX64.EFI` fallback and `--removable` gated on `_esp_safe` check (target ESP must be on `$DISK`)

- **CachyOS GDM "Session never registered" / wrong password on reboot**: after `pacman -Syu` + reboot, `/tmp/.X11-unix` recreated with `gdm-greeter:gdm 1755` ownership ~10s after `systemd-tmpfiles-setup` exits. XWayland socket creation fails → `gnome-shell` crashes → GDM loops. Fixed with three independent layers:
  1. `/etc/tmpfiles.d/zz-dc-x11-unix.conf` (processed last, every boot)
  2. `dc-x11-unix-enforce.service` — `chown root:root + chmod 1777` every boot, `Before=display-manager.service`
  3. `dc-firstboot.service` safety net on first boot

- **snapper: `/.snapshots` missing after install** — rsync excludes `/.snapshots` from source to avoid phantom host snapshots on the clone. Target has no `/.snapshots` dir even though Calamares copies `@`. `snapper create` fails with `path:/.snapshots errno:2`. Fixed: `dc-firstboot.service` creates `/.snapshots` as btrfs subvolume if missing.

- **Live initramfs leftover in `/boot/`**: squashfs extraction copies `initramfs-*-live.img` (50–200 MB) to the installed target `/boot/`. Fixed: `dc-final-fixes.sh` removes `*-live.img` / `*-live.img` patterns without touching versioned default kernels or plain `vmlinuz` symlink.

---

#### openSUSE Tumbleweed (23 bugs fixed during development)

- **No C++ Calamares modules**: openSUSE ships Calamares without `partition.so` and `unpackfs.so` (uses YaST natively). DistroClone detects this and falls back to a pure shellprocess pipeline: `setrootmount → disk-setup → extract-squashfs → … → rebuild-initramfs → grubinstall → dc-final-fixes → umount`.

- **`/home/<user>` not created after install**: btrfs `@/home` subvolume mounted at boot hides content created at install time. Fixed via `dc-firstboot.service` + `dc-write-fstab.sh` btrfs subvolume detection.

- **Root password not set**: `doReusePassword: false` + missing fallback left root account locked. Fixed: `doReusePassword: true` + explicit shadow hash check + fallback in `dc-post-users.sh`.

- **`systemctl` hangs in chroot**: `enable/disable/mask/daemon-reload` block waiting for dbus (not running in chroot). All `systemctl` calls replaced with manual symlink operations (`ln -sf /dev/null /etc/systemd/system/...`).

- **`/boot/loader/` in wrong location**: BLS entries written to `/boot/loader/` instead of `/boot/efi/loader/`. Fixed by `dc-final-fixes.sh` moving the directory after `grub-install`.

- **Autologin persists after install**: `sddm.conf.d/autologin.conf` (written for the live session) survives into the squashfs. Fixed by `dc-final-fixes.sh` writing explicit override files (highest-priority prefix `zz-`) for SDDM, GDM, and openSUSE `sysconfig/displaymanager`.

- **auditd 90-second boot delay**: `auditd.service` inherited from live squashfs; kernel audit framework unavailable in VM. Fixed: `cleanup-live-conf` masks `auditd.service`.

- **fstab btrfs subvolume entries missing**: `btrfs subvolume list | while read` pipeline ran in a subshell — variables lost, silent failure, zero entries written. Fixed by capturing output once into a variable, iterating over explicit known pairs, and logging every skip to the Calamares log.

- **GRUB VFS crash, stale BLS entries, dracut hang, kpmcore6, kiwi-live initramfs**: see full session notes in `project_dc_opensuse_calamares.md`.

---

#### Fedora / RPM Family

- **LUKS kernel parameter**: Arch requires `cryptdevice=UUID=...:luks-...`, Fedora requires `rd.luks.uuid=...`. `dc-crypto.sh` detects family and injects the correct parameter.

- **Empty GRUB menu from `GRUB_ENABLE_BLSCFG=false`**: Fedora requires BLS. Fixed: `dc-grub.sh` ensures `GRUB_ENABLE_BLSCFG=true` in `/etc/default/grub` before `grub2-mkconfig`.

- **Empty BLS entries after dracut**: BLS entry written before dracut regenerates initramfs → stale `initrd` path. Fixed: BLS entry patched after dracut completes.

- **`filesystem: "ext4"` override on btrfs Fedora**: same root cause as CachyOS. Fixed by same `findmnt` detection. `/boot` entry keeps `filesystem: "ext4"` hardcoded (BLS requirement — GRUB reads kernel pre-decrypt from ext4 `/boot`).

---

### Known Limitations

- **openSUSE / Garuda GRUB snapshot submenu**: empty after install. Root cause: default btrfs subvolume is top-level ID 5, but `grub2-snapper-plugin` / `grub-btrfs` expect the `snapper-rollback` layout. Snapper CLI + YaST work correctly. Run `sudo grub-mkconfig` manually after creating snapshots to populate the menu.
- **`@snapshots` fstab entry**: Calamares does not auto-generate a dedicated fstab mount for `@snapshots`. `dc-firstboot.service` creates `/.snapshots` as a child subvolume; a separate fstab entry can be added manually.
- **Root required**: `rsync --one-file-system` and `mksquashfs` need root. Run with `sudo`.
- **Source must be the running system**: offline cloning of a mounted partition is not supported.

---

### Notes

- Inspired by [penguins-eggs](https://github.com/pieroproietti/penguins-eggs) (Piero Proietti, MIT) — family detection logic and dependency maps adapted from its TypeScript distro classes.
- Debian/Ubuntu family: use the separate [distroClone](https://github.com/fconidi/distroClone) branch + `.deb` package.
