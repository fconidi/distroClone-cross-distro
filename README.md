# DistroClone Cross-Distro



<img width="256" height="256" alt="distroClone" src="https://github.com/user-attachments/assets/bbdee7b1-d80f-4c30-875a-7be997810de4" />




> Create a bootable, installable ISO from your running Linux system — no matter which distribution you use.

DistroClone Cross-Distro clones a live Linux system into a fully functional ISO image with a guided installer (Calamares). Boot the ISO on any compatible machine and install an exact replica of the source system: packages, configuration, users, filesystem layout, LUKS encryption, and btrfs subvolumes all included.

Distributed as a single self-contained **AppImage**. No installation. No dependencies to manage on the host.

---

## Supported Distributions


<img width="256" height="166" alt="opensuse" src="https://github.com/user-attachments/assets/48620bc5-11e6-4ac5-96ad-d007a5b0e719" /> <img width="256" height="256" alt="manjaro" src="https://github.com/user-attachments/assets/3d72d9be-5658-4984-a774-33f5c6722267" />
<img width="256" height="256" alt="Garuda" src="https://github.com/user-attachments/assets/7bafaaa1-8e10-46fb-92bd-d3b85f1308eb" /> <img width="256" height="141" alt="fedora" src="https://github.com/user-attachments/assets/72f974a9-3904-4515-8a8a-3ef713e0a2a9" /> <img width="256" height="250" alt="EndeavourOS-logo" src="https://github.com/user-attachments/assets/529bafbb-cfcb-47e0-b1f7-71ab94bb8a94" />
<img width="256" height="256" alt="cachyos" src="https://github.com/user-attachments/assets/019572d4-11de-4e55-88dc-c03d1b5e4231" /> <img width="256" height="256" alt="archlinux" src="https://github.com/user-attachments/assets/98a454a1-a0e7-41bd-b4d0-ab8997b9ebe6" />



| Distribution | Family | Initramfs | Bootloader | btrfs | LUKS |
|---|---|---|---|---|---|
| Arch Linux | arch | mkinitcpio | GRUB (archiso) | ✓ | ✓ |
| CachyOS | arch | mkinitcpio | GRUB + grub-btrfs | ✓ snapper | ✓ |
| EndeavourOS | arch | mkinitcpio | GRUB (archiso) | ✓ | ✓ |
| Garuda Linux | arch | dracut | GRUB | ✓ | ✓ |
| Manjaro | arch | mkinitcpio | GRUB | ✓ | ✓ |
| Fedora | fedora | dracut | GRUB2 + BLS | ✓ | ✓ |
| openSUSE Tumbleweed | opensuse | dracut | GRUB2 + BLS | ✓ snapper | ✓ |

> **Debian/Ubuntu family** → separate branch + `.deb` package:
> [github.com/fconidi/distroClone](https://github.com/fconidi/distroClone) · [distroClone_1.3.4_all.deb](https://sourceforge.net/projects/distroclone/files/v1.3.4/distroClone_1.3.4_all.deb/download)

---

## Quick Start

```bash
# Download and make executable
chmod +x distroClone-1.3.6-x86_64.AppImage

# Detect your distribution family (dry run)
sudo ./distroClone-1.3.6-x86_64.AppImage --detect

# Install required dependencies
sudo ./distroClone-1.3.6-x86_64.AppImage --install-deps

# Run the full clone
sudo ./distroClone-1.3.6-x86_64.AppImage
```

The process is interactive. It prints progress at each of its 30 labeled steps, from distribution detection through ISO assembly.

---

## Architecture

### Repository Layout

```
distroClone-cross-distro/
├── DistroClone.sh          # Main orchestrator (~5400 lines)
├── distro-detect.sh        # Distribution + feature detection
├── calamares-config.sh     # Calamares installer configurator (family-agnostic core)
├── calamares-config-arch.sh  # Arch-family Calamares overrides
├── calamares-config-fedora.sh # Fedora/openSUSE Calamares overrides
├── dc-crypto.sh            # LUKS crypto entry point
├── dc-initramfs.sh         # initramfs rebuild backends (mkinitcpio / dracut)
├── dc-grub.sh              # GRUB install + mkconfig + BLS + snapper gating
└── build-appimage.sh       # AppImage build pipeline
```

### Execution Pipeline

```
DistroClone.sh
│
├─ [1]  distro-detect.sh          → DC_FAMILY, DC_DISTRO_ID, DC_KERNEL_FLAVOR,
│                                    DC_INITRAMFS, DC_LIVE_STACK
│
├─ [2-7]  Host preparation        → install deps, build live kernel/initramfs,
│                                    configure GRUB for live session
│
├─ [8]  rsync SOURCE → DEST       → full system clone (selective excludes:
│         /proc /sys /dev /run     /tmp /.snapshots /var/lib/snapper /swap …)
│
├─ [9-15] DEST cleanup            → remove live users, autologin, snapper host
│         snapper state gating    state (openSUSE-only), restore snapper config
│         (Task 1 / 2026-04-18)   for Arch family via copy-back from SOURCE
│
├─ [16-19] Family-specific chroot → CHROOT_ARCH_EOF / CHROOT_FEDORA_EOF
│    │
│    ├─ Arch:  mkinitcpio, archiso hooks, GRUB, services cleanup,
│    │         dc-firstboot.service, dc-x11-unix-enforce.service,
│    │         tmpfiles.d drop-in, Calamares config (calamares-config.sh)
│    │
│    └─ openSUSE/Fedora: dracut, grub2, BLS entries, Calamares config
│
├─ [20-22] Calamares config       → calamares-config.sh writes out the full
│          generation             Calamares module tree inside the squashfs
│
├─ [23]  mksquashfs DEST          → compressed squashfs (zstd or xz)
│         snapper config gating:  etc/snapper/configs/root excluded only
│         (2026-04-18)            on opensuse; preserved on Arch
│
├─ [24-28] ISO assembly           → xorriso + ISOLINUX/UEFI stubs, GRUB EFI,
│                                    GRUB BIOS, hybrid MBR
│
└─ [29-30] Validation + output    → file size check, magic bytes, usage hint
```

---

### Distribution Detection (`distro-detect.sh`)

Detection uses a priority chain:

1. `/etc/os-release` → `ID` field → exact match against a known-distro table
2. `ID_LIKE` field → family fallback for unlisted derivatives
3. Sentinel files (`/etc/arch-release`, `/etc/fedora-release`, `/etc/SuSE-release`)

Produces exported variables consumed throughout the pipeline:

| Variable | Values | Purpose |
|---|---|---|
| `DC_FAMILY` | `arch` `fedora` `opensuse` `debian` `alpine` | Selects code paths |
| `DC_DISTRO_ID` | `cachyos` `garuda` `endeavouros` … | Fine-grained overrides |
| `DC_INITRAMFS` | `mkinitcpio` `dracut` | initramfs backend |
| `DC_KERNEL_FLAVOR` | `cachyos` `zen` `hardened` `lts` `generic` | Kernel variant |
| `DC_LIVE_STACK` | `archiso` `dracut-live` | Live boot mechanism |

---

### Calamares Configuration Pipeline

`calamares-config.sh` is the most complex component (~2200 lines). It runs **inside the squashfs chroot** and builds the entire Calamares module tree from scratch, adapting every setting to the detected family.

Key modules written:

| Module | Purpose |
|---|---|
| `welcome.conf` | Minimum RAM/disk checks, locale |
| `partition.conf` | Filesystem defaults, btrfs subvolume layout |
| `fstab.conf` | Mount options per filesystem type |
| `bootloader.conf` | GRUB/systemd-boot target, EFI id |
| `shellprocess_*` | Custom pre/post install scripts |
| `packages.conf` | Packages to remove (calamares, live tools) |
| `services-systemd.conf` | Services to disable (live-only units) |
| `displaymanager.conf` | Autologin removal |
| `users.conf` | Password hashing, `doReusePassword` |

The `shellprocess` pipeline executes family-specific scripts in the installed target chroot at install time. For Arch, this runs:
1. Partition subvolume creation/detection
2. fstab validation and emergency repair
3. `dc-crypto.sh` (LUKS + initramfs + GRUB) via `calamares-grub-install.sh`
4. `dc-firstboot.service` installation
5. Final autologin/password safety nets

---

### Crypto Layer (`dc-crypto.sh` / `dc-initramfs.sh` / `dc-grub.sh`)

These three scripts are **generated at ISO-build time** by `calamares-config.sh` (written into `/usr/local/lib/distroClone/` inside the squashfs) and sourced at **Calamares install time** inside the target chroot.

```
dc-crypto.sh          ← entry point, detects LUKS UUID, calls backends
  ├─ dc-initramfs.sh  ← mkinitcpio (Arch) or dracut (Fedora/openSUSE)
  └─ dc-grub.sh       ← GRUB install + mkconfig + BLS + btrfs rootflags
```

**LUKS detection** reads `/proc/mounts` and `blkid` to find the LUKS UUID of the root block device at Calamares time (not ISO-build time). This ensures the clone always references the target's actual LUKS partition, not the source's.

**btrfs rootflags**: if root is btrfs with a `@` subvolume, `dc_configure_btrfs_rootflags()` injects `rootflags=subvol=@` into:
- `/etc/default/grub` → `GRUB_CMDLINE_LINUX`
- `/etc/kernel/cmdline` (Fedora BLS)
- Existing BLS entries in `/boot/loader/entries/*.conf`

**Snapper gating** in `dc-grub.sh`: before running `grub-mkconfig`, the script purges `/.snapshots/*` host snapshot subvolumes (always) but removes `/etc/snapper/configs/root` only when `DC_FAMILY=opensuse`. On Arch family the config is preserved so snapper works immediately after install.

---

### btrfs + Snapper Support

#### openSUSE Tumbleweed

- **Layout**: nested subvolumes (`@`, `@/home`, `@/var`, `@/usr/local`, `@/srv`, `@/opt`, `@/root`, `@/.snapshots`)
- **Bootloader**: BLS (Boot Loader Specification) via `kernel-install`; kernels live at `/boot/efi/<machine-id>/<kver>/linux`
- **Snapper**: `dc-firstboot.service` runs `snapper create-config /` + baseline snapshot + optional `grub2-snapper-plugin` install (requires internet). GRUB snapshot menu currently shows empty entries due to an architectural mismatch (default subvolume is ID 5, not a snapper-rollback layout); snapper itself and YaST work correctly.

#### Garuda Linux

- **Layout**: flat subvolumes (`@`, `@home`) — simpler than CachyOS (no `@snapshots`, `@log`, etc. by default)
- **Bootloader**: GRUB 2.14 with btrfs driver in Garuda-patched build. Key invariants for correct boot:
  - btrfs default subvolume must remain **ID 5 (top-level)** — `set-default @` is intentionally skipped on Garuda, because Garuda's GRUB btrfs driver reads paths from the top-level and navigates into `@` as a subvolume directory
  - grub.cfg kernel paths use the `/@/boot/vmlinuz-*` prefix (Garuda-native style), not the stripped `/boot/` form used on other Arch variants
  - **Extent layout fix** (`dc_defrag_boot_files_btrfs`): rsync creates kernel/initramfs files with sparse or multi-extent btrfs layout that Garuda's GRUB btrfs driver cannot read → "premature end of file `/@/boot/vmlinuz-linux-zen`". Fixed by rewriting all `/boot/vmlinuz-*`, `/boot/initramfs-*.img`, and `/boot/*-ucode.img` files with `cp --sparse=never` followed by `btrfs filesystem defragment -r /boot/` before `grub-install`. Verified: single contiguous extent → GRUB reads correctly.
- **Dual-disk ESP safety**: when installing a Garuda clone to a secondary disk (`sdb`) alongside an existing Garuda install on `sda`, three safeguards prevent overwriting the original ESP:
  1. `bootloader-id` is always suffixed with `Clone` (e.g. `GarudaClone`) — avoids NVRAM/ESP directory collision with `EFI/Garuda/`
  2. Global `blkid` ESP search removed — ESP is resolved only from the target disk (`$DISK`)
  3. `EFI/BOOT/BOOTX64.EFI` fallback and `--removable` are gated on `_esp_safe` check: `findmnt -n -o SOURCE /boot/efi | lsblk pkname == $DISK`
- **Snapper**: `dc-firstboot.service` creates snapper config + baseline snapshot. Full snapper + YaST support. GRUB snapshot submenu empty (architectural mismatch, same as openSUSE — default subvol is ID 5, not snapper-rollback layout).

#### CachyOS (and Arch btrfs variants)

- **Layout**: flat subvolumes (`@`, `@home`, `@root`, `@srv`, `@var/cache`, `@var/log`, `@var/tmp`, `@snapshots`)
- **Clone flow**:
  1. `rsync` excludes `/.snapshots` and `/etc/snapper/configs/root` from source
  2. `copy-back`: after rsync, `DistroClone.sh` restores `etc/snapper/configs/root` from source (non-openSUSE families only)
  3. `mksquashfs` excludes `etc/snapper/configs/root` only on openSUSE; on Arch it travels inside the squashfs
  4. `dc-firstboot.service` (first boot of installed system):
     - if `/.snapshots` missing → `btrfs subvolume create /.snapshots`
     - if snapper config missing → `snapper -c root create-config /`
     - creates "DistroClone baseline" snapshot
     - enables `grub-btrfs-snapper.service` or `grub-btrfsd.service` (whichever is present)
     - runs `grub-mkconfig` to populate the snapshot submenu
     - enables `snapper-timeline.timer` + `snapper-cleanup.timer`
- **GRUB snapshot menu**: works natively via `grub-btrfs`, which reads the `@snapshots` subvolume and generates a submenu at every snapshot creation.

---

### Emergency fstab Repair

If Calamares' own fstab module produces an incomplete or broken `/etc/fstab`, `calamares-config.sh` includes an emergency fallback that:

1. Detects the root block device UUID via `blkid`
2. Lists btrfs subvolumes with `btrfs subvolume list`
3. Maps subvolume paths to mountpoints, covering both layouts:

```bash
# nested (openSUSE)        # flat (CachyOS/Arch)
@/home  → /home            @home      → /home
@/var   → /var             @var/cache → /var/cache
@/srv   → /srv             @var/log   → /var/log
@/root  → /root            @var/tmp   → /var/tmp
@/.snapshots → /.snapshots @snapshots → /.snapshots
```

4. Writes a syntactically valid fstab and logs the result

---

### First-Boot Service (`dc-firstboot.service`)

A `systemd` oneshot service installed on the target system. Runs once (guarded by `/var/lib/distroClone-firstboot-done`). Responsibilities:

- Creates missing `/home/<user>` directories (btrfs subvolume mount can hide content created at install time)
- Unlocks accounts with shadow hash prefix `!$` (locked-but-valid hash)
- **openSUSE**: snapper config + `grub2-snapper-plugin` + timers
- **Arch family**: `/.snapshots` creation, snapper baseline, `grub-btrfs-snapper.service` / `grub-btrfsd.service` enable, `grub-mkconfig`, snapper timers
- Safety net: re-applies `/tmp/.X11-unix` ownership fix (`chown root:root; chmod 1777`) in case `dc-x11-unix-enforce.service` has not yet run

---

### XWayland / GDM Stability Fix (`dc-x11-unix-enforce.service`)

**CachyOS-specific** (and defensive for any Arch/GNOME Wayland system).

**Root cause**: on CachyOS after a `pacman -Syu` + reboot, `/tmp/.X11-unix` is recreated ~10 seconds after `systemd-tmpfiles-setup.service` exits, with ownership `gdm-greeter:gdm` and mode `1755`. XWayland refuses to create its socket → `gnome-shell` crashes → `GdmSessionWorker: Session never registered` → GDM returns to greeter (appears as "wrong password" even though TTY login works).

**Defense-in-depth approach** (three independent layers):

| Layer | Mechanism | When |
|---|---|---|
| 1 | `/etc/tmpfiles.d/zz-dc-x11-unix.conf`: `d /tmp/.X11-unix 1777 root root 10d` | Every boot, via `systemd-tmpfiles-setup.service` |
| 2 | `dc-x11-unix-enforce.service`: `chown root:root + chmod 1777` | Every boot, `After=tmpfiles-setup`, `Before=display-manager.service` |
| 3 | `dc-firstboot.sh` safety net | First boot only |

The `zz-` prefix on the tmpfiles drop-in ensures it is processed after all vendor rules in `/usr/lib/tmpfiles.d/`.

---

### AppImage Build (`build-appimage.sh`)

The AppImage bundles all scripts into a squashfs-based self-extracting executable:

```
distroClone-1.3.6-x86_64.AppImage
└── squashfs-root/
    ├── AppRun                    ← entry point, dispatches to DistroClone.sh
    ├── usr/share/distroClone/
    │   ├── DistroClone.sh
    │   ├── distro-detect.sh
    │   ├── calamares-config.sh
    │   ├── calamares-config-arch.sh
    │   ├── calamares-config-fedora.sh
    │   ├── dc-crypto.sh
    │   ├── dc-initramfs.sh
    │   └── dc-grub.sh
    └── distroClone.desktop
```

**After every script change**, the AppImage must be rebuilt before building the ISO — the squashfs bakes the scripts at `mksquashfs` time and no longer reads from disk:

```bash
bash build-appimage.sh
```

Verification: extract and grep the new AppImage to confirm changes are inside:
```bash
./distroClone-1.3.6-x86_64.AppImage --appimage-extract
grep 'your_change' squashfs-root/usr/share/distroClone/calamares-config.sh
```

---

## Key Design Invariants

1. **Never `systemctl` inside a chroot** — `systemd` is not running; use manual symlinks in `/etc/systemd/system/*.wants/`.
2. **Never `exec >file` in shellprocess scripts** — output redirection via exec breaks the Calamares log stream; use `tee` instead.
3. **Always `export PATH` with sbin paths** — Calamares shellprocess may not inherit a full PATH; tools like `grub-install` live in `/usr/sbin`.
4. **Mount child directories after parents** — in the Calamares fstab/mount sequence, `/boot` must be mounted before `/boot/efi`.
5. **Never `cmd | while read`** for state-collecting loops — subshell variables are lost after the pipe. Use `var=$(cmd)` + explicit iteration.
6. **Snapper cleanup is family-gated** — destroying `/etc/snapper/configs/root` is correct for openSUSE (will be recreated by dc-firstboot) but wrong for CachyOS (config must be preserved from source).
7. **btrfs boot files must be rewritten before grub-install** — `rsync` creates kernel/initramfs files with sparse or multi-extent extent layout that GRUB btrfs drivers (tested: Garuda GRUB 2.14) cannot read, producing "premature end of file". `dc_defrag_boot_files_btrfs()` rewrites all `/boot/vmlinuz-*`, `/boot/initramfs-*.img`, `/boot/*-ucode.img` with `cp --sparse=never` + `btrfs filesystem defragment -r /boot/` before `grub-install`. No-op on non-btrfs.
8. **Never share ESP across clone and original on same machine** — `bootloader-id` must be unique per install (`{Distro}Clone`) and ESP mount must be validated against the target disk (`$DISK`) before writing any EFI file. Global `blkid` ESP search is unsafe in multi-disk setups.
9. **`partitionLayout` rootfs `filesystem:` must mirror the source `/` filesystem** — derive it at build time via `findmnt -no FSTYPE /` so btrfs-native distros (Garuda / CachyOS / openSUSE) produce btrfs targets and ext4-native distros produce ext4. Omitting the key makes Calamares create the partition as `unformatted` (broken install). Hardcoding a fixed value (e.g. `ext4`) overrides `defaultFileSystemType` and the UI dropdown → every "Erase disk" install produces that filesystem regardless of user choice. `defaultFileSystemType` is set to the same detected value to match the dropdown preselection. Users wanting a different target filesystem must either rebuild DistroClone on a differently-formatted source or use Manual partitioning. The Fedora/openSUSE `/boot` entry keeps `filesystem: "ext4"` hardcoded (BLS requirement).

---

## Known Limitations

- **openSUSE / Garuda GRUB snapshot menu**: the snapshot boot submenu is empty on both distros. Root cause: default btrfs subvolume is top-level ID 5, but `grub2-snapper-plugin` / `grub-btrfs` expect the `snapper-rollback` layout. Snapper itself (CLI + YaST/GUI) works correctly. Submenu can be populated manually after install by running `sudo grub-mkconfig -o /boot/grub/grub.cfg` with snapshots present.
- **`/etc/fstab` for `@snapshots`**: Calamares does not auto-generate a dedicated fstab entry for the `@snapshots` subvolume. `dc-firstboot.service` creates `/.snapshots` as a child subvolume of `@`, which is functional but differs from the canonical CachyOS peer layout. A separate mount entry can be added manually.
- **Requires root**: `rsync --one-file-system` and `mksquashfs` need root. The AppImage must be run with `sudo`.
- **Source must be the running system**: DistroClone clones from `/` of the current boot. Offline cloning of a mounted partition is not supported.

---

## Related Projects

- **distroClone (Debian/Ubuntu)**: [github.com/fconidi/distroClone](https://github.com/fconidi/distroClone)
- **Calamares**: [calamares.io](https://calamares.io)
- **grub-btrfs**: [github.com/Antynea/grub-btrfs](https://github.com/Antynea/grub-btrfs)
- **snapper**: [snapper.io](http://snapper.io)

---

## License

GPL-3.0 — see [LICENSE](LICENSE).
