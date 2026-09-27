# DistroClone Cross-Distro — Clone Your Linux System to Any Machine

Have you ever wanted to take your Linux system exactly as it is — software, settings, users — and bring it to a new drive, a new PC, or share it with someone else? **DistroClone Cross-Distro** does exactly that.

---

## What Is DistroClone Cross-Distro?

DistroClone Cross-Distro is an open source tool that creates a **bootable live ISO** from your running Linux system and turns it into a full installer powered by **Calamares** — the installation framework used by dozens of distributions worldwide.

The resulting ISO can be:
- flashed to a USB drive
- booted on any compatible machine
- used to install an exact copy of your system in just a few clicks

This is not a simple backup: it's an **installable snapshot** of your entire Linux environment.

---

## How It Works

DistroClone is distributed as an **AppImage** — no installation required, no dependency headaches:

```bash
# Launch DistroClone (requires root)
sudo ./distroClone-1.3.6-x86_64.AppImage
```

The process is fully guided:

1. **Auto-detection** of the source distribution (family, kernel, initramfs tool)
2. **rsync cloning** of the running system into a staging directory
3. **Calamares configuration** adapted to the distro family (Arch, Fedora, openSUSE…)
4. **squashfs creation** and live ISO assembly
5. **Ready-to-flash ISO** — write it with Etcher, Ventoy, or `dd`

---

## Tested Distributions

DistroClone Cross-Distro has been successfully tested on:

| Distribution | Family | Notes |
|---|---|---|
| **Arch Linux** | Arch | Full support |
| **CachyOS** | Arch | btrfs + snapper + grub-btrfs |
| **Garuda Linux** | Arch | btrfs + snapper + grub-btrfs, KDE Dragonized; dual-disk ESP safe |
| **EndeavourOS** | Arch | mkinitcpio + archiso |
| **Manjaro** | Arch | Full support |
| **Fedora** | Fedora | dracut, GRUB2 + BLS, btrfs |
| **openSUSE Tumbleweed** | openSUSE | btrfs, snapper, BLS bootloader |

### LUKS Encryption

Systems running with **LUKS full-disk encryption** are fully supported: the correct kernel parameters (`cryptdevice=`, `rd.luks.uuid=`) are automatically injected into the cloned system's bootloader.

### btrfs and Snapper (CachyOS / Garuda / openSUSE)

On distributions using **btrfs + snapper**, DistroClone:
- preserves the subvolume layout (`@home`, `@snapshots`, etc.)
- automatically enables **snapper** and **grub-btrfs** on the first boot of the clone
- creates a "DistroClone baseline" snapshot the first time the cloned system boots

---

## Key Benefits

- **No fresh install needed**: bring your environment exactly as it is, skip reconfiguring everything from scratch
- **Hardware migration**: move to a new PC without losing anything
- **Sharing**: distribute your setup to colleagues, friends, or students
- **Installable backup**: not just file restoration — restores a fully working system
- **Hardware-independent**: Calamares handles the installation phase, adapting the bootloader and initramfs to the target machine
- **No installation required**: runs as an AppImage, leaves your host system untouched

---

## Debian/Ubuntu Version

For **Debian-based** distributions (Ubuntu, Linux Mint, Pop!\_OS, etc.) there is a dedicated branch with a `.deb` package:

- **GitHub:** [github.com/fconidi/distroClone](https://github.com/fconidi/distroClone)
- **Sourceforge:** [distroClone v1.3.4 .deb](https://sourceforge.net/projects/distroclone/files/v1.3.4/distroClone_1.3.4_all.deb/download)

---

## Get Started

**GitHub:** [github.com/fconidi/distroClone-cross-distro](https://github.com/fconidi/distroClone-cross-distro)

```bash
# Download the AppImage (cross-distro: Arch, openSUSE, Fedora, ...)
chmod +x distroClone-1.3.6-x86_64.AppImage

# Launch
sudo ./distroClone-1.3.6-x86_64.AppImage
```

---

*Coming soon: a deep-dive technical post covering the internal architecture, the Calamares pipeline, btrfs subvolume management, and the LUKS crypto layer.*
