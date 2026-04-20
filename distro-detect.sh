#!/bin/bash
# =============================================================================
# distro-detect.sh — DistroClone cross-distro detection & dependency manager
# =============================================================================
# Inspired by penguins-eggs (Piero Proietti, MIT License)
# Adapted for DistroClone by Franco Conidi aka edmond <fconidi@gmail.com>
#
# Usage: source distro-detect.sh
# After sourcing, the available variables are:
#   DC_FAMILY      → debian | arch | fedora | opensuse | alpine
#   DC_DISTRO_ID   → debian | ubuntu | arch | fedora | opensuse | etc.
#   DC_CODENAME    → trixie | noble | etc. (only for debian-family)
#   DC_PKG_MANAGER → apt | pacman | dnf | zypper | apk
#   DC_PKG_INSTALL → installation command (e.g. "apt install -y")
#   DC_PKG_UPDATE  → index update command
#
# Public functions:
#   dc_detect_distro          → detects everything and populates the variables
#   dc_check_dependencies     → checks missing dependencies
#   dc_install_dependencies   → installs dependencies for the current family
#   dc_print_distro_info      → prints summary of the detected system
# =============================================================================

# ── Colors for output ────────────────────────────────────────────────────────
_DC_RED='\033[0;31m'
_DC_GREEN='\033[0;32m'
_DC_YELLOW='\033[1;33m'
_DC_BLUE='\033[0;34m'
_DC_CYAN='\033[0;36m'
_DC_RESET='\033[0m'
_DC_BOLD='\033[1m'

_dc_info()    { echo -e "${_DC_CYAN}[DC]${_DC_RESET} $*"; }
_dc_ok()      { echo -e "${_DC_GREEN}[✓]${_DC_RESET} $*"; }
_dc_warn()    { echo -e "${_DC_YELLOW}[!]${_DC_RESET} $*"; }
_dc_error()   { echo -e "${_DC_RED}[✗]${_DC_RESET} $*" >&2; }
_dc_section() { echo -e "\n${_DC_BOLD}${_DC_BLUE}━━ $* ━━${_DC_RESET}"; }

# =============================================================================
# DISTRIBUTION DETECTION
# Inspired by: penguins-eggs/src/classes/distro.ts — Distro class
# =============================================================================
dc_detect_distro() {
    _dc_section "Detection distro"

    # Read /etc/os-release (standard freedesktop)
    if [ ! -f /etc/os-release ]; then
        _dc_error "/etc/os-release not found. System not supported."
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    DC_DISTRO_ID="${ID:-unknown}"
    DC_DISTRO_ID_LIKE="${ID_LIKE:-}"
    DC_CODENAME="${VERSION_CODENAME:-}"
    DC_DISTRO_PRETTY="${PRETTY_NAME:-$ID}"
    DC_VERSION_ID="${VERSION_ID:-}"

    # ── Family detection ─────────────────────────────────────────────────────
    # Logic: checks ID first, then ID_LIKE, then sentinel file
    # (same approach as penguins-eggs Distro class → familyId())

    DC_FAMILY=""

    # Debian family
    case "$DC_DISTRO_ID" in
        debian|ubuntu|linuxmint|kali|neon|popos|lmde|devuan|raspbian|parrot|mx|antix|deepin|zorin|elementary|bodhi|peppermint|tails)
            DC_FAMILY="debian" ;;
    esac

    # Arch family
    if [ -z "$DC_FAMILY" ]; then
        case "$DC_DISTRO_ID" in
            arch|manjaro|endeavouros|garuda|arcolinux|artix|cachyos|biglinux|blendos|crystal)
                DC_FAMILY="arch" ;;
        esac
    fi

    # Fedora / RPM family
    if [ -z "$DC_FAMILY" ]; then
        case "$DC_DISTRO_ID" in
            fedora|rhel|centos|almalinux|rocky|ol|nobara|ultramarine|bazzite)
                DC_FAMILY="fedora" ;;
        esac
    fi

    # openSUSE family
    if [ -z "$DC_FAMILY" ]; then
        case "$DC_DISTRO_ID" in
            opensuse*|sles|sled|tumbleweed|leap)
                DC_FAMILY="opensuse" ;;
        esac
    fi

    # Alpine
    if [ -z "$DC_FAMILY" ]; then
        case "$DC_DISTRO_ID" in
            alpine) DC_FAMILY="alpine" ;;
        esac
    fi

    # Fallback to ID_LIKE (for derivatives not explicitly mapped)
    if [ -z "$DC_FAMILY" ] && [ -n "$DC_DISTRO_ID_LIKE" ]; then
        case "$DC_DISTRO_ID_LIKE" in
            *debian*|*ubuntu*) DC_FAMILY="debian" ;;
            *arch*)            DC_FAMILY="arch" ;;
            *fedora*|*rhel*)   DC_FAMILY="fedora" ;;
            *suse*)            DC_FAMILY="opensuse" ;;
        esac
    fi

    # Fallback to sentinel file (last resort)
    if [ -z "$DC_FAMILY" ]; then
        [ -f /etc/debian_version ] && DC_FAMILY="debian"
        [ -f /etc/arch-release ]   && DC_FAMILY="arch"
        [ -f /etc/fedora-release ] && DC_FAMILY="fedora"
        [ -f /etc/alpine-release ] && DC_FAMILY="alpine"
        [ -f /etc/SuSE-release ]   && DC_FAMILY="opensuse"
    fi

    if [ -z "$DC_FAMILY" ]; then
        _dc_error "Unrecognized distribution family: $DC_DISTRO_ID"
        _dc_error "DistroClone supports: Debian/Ubuntu, Arch, Fedora, openSUSE, Alpine"
        exit 1
    fi

    # ── Package manager per family ──────────────────────────────────────────
    case "$DC_FAMILY" in
        debian)
            DC_PKG_MANAGER="apt"
            DC_PKG_UPDATE="apt-get update"
            DC_PKG_INSTALL="apt-get install -y"
            DC_PKG_CHECK="dpkg-query -W -f='\${Status}' %s 2>/dev/null | grep -q 'install ok installed'"
            ;;
        arch)
            DC_PKG_MANAGER="pacman"
            DC_PKG_UPDATE="pacman -Sy --noconfirm"
            DC_PKG_INSTALL="pacman -S --noconfirm --needed"
            DC_PKG_CHECK="pacman -Q %s >/dev/null 2>&1"
            ;;
        fedora)
            DC_PKG_MANAGER="dnf"
            DC_PKG_UPDATE="dnf makecache -y"
            DC_PKG_INSTALL="dnf install -y"
            DC_PKG_CHECK="rpm -q %s >/dev/null 2>&1"
            ;;
        opensuse)
            DC_PKG_MANAGER="zypper"
            DC_PKG_UPDATE="zypper refresh"
            DC_PKG_INSTALL="zypper install -y --no-recommends"
            DC_PKG_CHECK="rpm -q %s >/dev/null 2>&1"
            ;;
        alpine)
            DC_PKG_MANAGER="apk"
            DC_PKG_UPDATE="apk update"
            DC_PKG_INSTALL="apk add"
            DC_PKG_CHECK="apk info -e %s >/dev/null 2>&1"
            ;;
    esac

    _dc_ok "Family: ${_DC_BOLD}$DC_FAMILY${_DC_RESET} | Distro: $DC_DISTRO_PRETTY"
    if [ -n "$DC_CODENAME" ]; then _dc_info "Codename: $DC_CODENAME"; fi
}

# =============================================================================
# FEATURE DETECTION — ARCH VARIANTS
# Distinguishes between archiso (Arch/CachyOS/EndeavourOS) and dracut-live (Garuda).
# Call AFTER dc_detect_distro(); no-op for non-arch families.
#
# Output variables (exported):
#   DC_INITRAMFS      → dracut | mkinitcpio
#   DC_KERNEL_FLAVOR  → zen | cachyos | hardened | lts | generic | custom
#   DC_LIVE_STACK     → dracut-live | archiso
# =============================================================================
dc_detect_arch_features() {
    [ "$DC_FAMILY" = "arch" ] || return 0

    # ── initramfs ────────────────────────────────────────────────────────────
    # Garuda installs dracut as a dependency of kernel-zen;
    # on Arch/CachyOS/EndeavourOS it is mkinitcpio
    if command -v dracut >/dev/null 2>&1; then
        DC_INITRAMFS="dracut"
    elif command -v mkinitcpio >/dev/null 2>&1; then
        DC_INITRAMFS="mkinitcpio"
    else
        DC_INITRAMFS="mkinitcpio"   # Arch standard fallback
    fi

    # ── kernel flavor ────────────────────────────────────────────────────────
    # pacman -Qq: fast, no output, exit 1 if package absent
    if   pacman -Qq linux-zen      >/dev/null 2>&1; then DC_KERNEL_FLAVOR="zen"
    elif pacman -Qq linux-cachyos  >/dev/null 2>&1; then DC_KERNEL_FLAVOR="cachyos"
    elif pacman -Qq linux-hardened >/dev/null 2>&1; then DC_KERNEL_FLAVOR="hardened"
    elif pacman -Qq linux-lts      >/dev/null 2>&1; then DC_KERNEL_FLAVOR="lts"
    elif pacman -Qq linux          >/dev/null 2>&1; then DC_KERNEL_FLAVOR="generic"
    else                                                  DC_KERNEL_FLAVOR="custom"
    fi

    # ── live stack ───────────────────────────────────────────────────────────
    # ALWAYS "archiso" for the entire Arch family, including Garuda/dracut.
    # Reason: CHROOT_ARCH_EOF installs mkinitcpio + mkinitcpio-archiso and
    # regenerates the initramfs with HOOKS=(base udev archiso ...) for ALL
    # Arch systems, including Garuda (Fix 40B/42/42B).
    # The HOST dracut block (dmsquash-live) is not needed and causes errors on Garuda
    # because it overwrites the correct initramfs already generated by the chroot.
    # DC_INITRAMFS documents what the host system uses (useful for debugging),
    # but does not determine the live stack of the ISO.
    DC_LIVE_STACK="archiso"

    export DC_INITRAMFS DC_KERNEL_FLAVOR DC_LIVE_STACK

    _dc_ok "Arch features: initramfs=${DC_INITRAMFS} | kernel=${DC_KERNEL_FLAVOR} | live-stack=${DC_LIVE_STACK}"
}

# =============================================================================
# CROSS-DISTRO DEPENDENCY MAP
# Inspired by: penguins-eggs/src/classes/pacman.d/{debian,archlinux,fedora}.ts
#
# Structure: each DC_DEPS_<FAMILY> variable contains package names
# specific to that family. "Common" dependencies use Debian names
# as a logical reference, then translated for each family.
# =============================================================================
_dc_define_deps() {

    # ──────────────────────────────────────────────────────────────────────────
    # DEBIAN FAMILY (Debian, Ubuntu, Mint, SysLinuxOS, LMDE, etc.)
    # Original .deb names — no translation needed
    # ──────────────────────────────────────────────────────────────────────────
    DC_DEPS_DEBIAN=(
        # ISO / boot tools
        "xorriso"
        "mtools"
        "syslinux-utils"
        "syslinux-common"
        "isolinux"
        "grub-pc-bin"
        "grub-efi-amd64-bin"
        # Filesystem / clone
        "rsync"
        "squashfs-tools"
        "fdisk"
        # Live system (Debian-specific)
        "live-boot"
        "live-config"
        "live-config-systemd"
        # Installer
        "calamares"
        "calamares-settings-debian"
        # Crypto
        "cryptsetup"
        "cryptsetup-initramfs"
        "cryptsetup-bin"
        # GUI tools
        "yad"
        "zenity"
        "imagemagick"
    )

    # ──────────────────────────────────────────────────────────────────────────
    # ARCH FAMILY (Arch, Manjaro, EndeavourOS, Garuda, etc.)
    # Sources: penguins-eggs/src/classes/pacman.d/archlinux.ts
    #          + manual research for AUR equivalents
    # NOTE: live-boot/live-config do not exist → use mkinitcpio + archiso hooks
    # NOTE: calamares-settings-debian does not exist → use vanilla calamares
    # ──────────────────────────────────────────────────────────────────────────
    DC_DEPS_ARCH=(
        # ISO / boot tools
        "libisoburn"           # contains xorriso
        "mtools"
        "syslinux"             # includes syslinux-utils + isolinux equivalent
        "grub"                 # includes grub-pc-bin and grub-efi
        "dosfstools"           # mkfs.vfat — required for efiboot.img [26/30]
        "erofs-utils"          # mkfs.erofs — used by archiso
        # Filesystem / clone
        "rsync"
        "squashfs-tools"
        "util-linux"           # includes fdisk (not available as a separate package on Arch)
        # Installer
        "calamares"            # from AUR or community repo
        # Crypto
        "cryptsetup"
        # GUI tools
        "yad"                  # from AUR
        "zenity"
        "imagemagick"
    )

    # ──────────────────────────────────────────────────────────────────────────
    # FEDORA FAMILY (Fedora, AlmaLinux, Rocky, Nobara, etc.)
    # Sources: penguins-eggs/src/classes/pacman.d/fedora.ts
    #          + penguins-eggs-deps.spec (RPM spec file in the repo)
    # NOTE: live-boot does not exist on RPM → use dracut (already included in the kernel)
    # NOTE: calamares-settings-debian does not exist → vanilla calamares
    # ──────────────────────────────────────────────────────────────────────────
    DC_DEPS_FEDORA=(
        # ISO / boot tools
        "xorriso"
        "mtools"
        "syslinux"             # includes isolinux
        "grub2-tools"          # grub-pc-bin equivalent
        "grub2-efi-x64"
        # Filesystem / clone
        "rsync"
        "squashfs-tools"
        "util-linux"           # includes fdisk
        # Live system (Fedora-specific — alternative to live-boot)
        "dracut"
        "dracut-live"          # dracut module for live ISO
        # Installer
        "calamares"
        # Crypto
        "cryptsetup"
        # GUI tools
        "yad"
        "zenity"
        "ImageMagick"          # note: capitalized on RPM
    )

    # ──────────────────────────────────────────────────────────────────────────
    # OPENSUSE FAMILY
    # Sources: penguins-eggs/src/classes/pacman.d/opensuse.ts
    # ──────────────────────────────────────────────────────────────────────────
    DC_DEPS_OPENSUSE=(
        "xorriso"
        "mtools"
        "syslinux"
        "grub2"
        "grub2-x86_64-efi"
        "rsync"
        "squashfs"
        "util-linux"
        "dracut"
        "calamares"
        "cryptsetup"
        "yad"
        "zenity"
        "ImageMagick"
    )

    # ──────────────────────────────────────────────────────────────────────────
    # ALPINE FAMILY
    # Sources: penguins-eggs/src/classes/pacman.d/alpine.ts
    # ──────────────────────────────────────────────────────────────────────────
    DC_DEPS_ALPINE=(
        "xorriso"
        "mtools"
        "syslinux"
        "grub"
        "grub-efi"
        "rsync"
        "squashfs-tools"
        "util-linux"
        "dracut"
        "cryptsetup"
        "imagemagick"
    )
}

# =============================================================================
# MISSING DEPENDENCY CHECK
# =============================================================================
dc_check_dependencies() {
    _dc_section "Check dependencies"
    _dc_define_deps

    local -n _DEPS="DC_DEPS_${DC_FAMILY^^}"
    DC_MISSING_DEPS=()

    for pkg in "${_DEPS[@]}"; do
        local check_cmd
        # Builds the package manager-specific check command
        case "$DC_FAMILY" in
            debian)
                if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
                    DC_MISSING_DEPS+=("$pkg")
                fi
                ;;
            arch)
                if ! pacman -Q "$pkg" >/dev/null 2>&1; then
                    DC_MISSING_DEPS+=("$pkg")
                fi
                ;;
            fedora|opensuse)
                if ! rpm -q "$pkg" >/dev/null 2>&1; then
                    DC_MISSING_DEPS+=("$pkg")
                fi
                ;;
            alpine)
                if ! apk info -e "$pkg" >/dev/null 2>&1; then
                    DC_MISSING_DEPS+=("$pkg")
                fi
                ;;
        esac
    done

    if [ ${#DC_MISSING_DEPS[@]} -eq 0 ]; then
        _dc_ok "All dependencies are satisfied"
        return 0
    else
        _dc_warn "Missing dependencies (${#DC_MISSING_DEPS[@]}): ${DC_MISSING_DEPS[*]}"
        return 1
    fi
}

# =============================================================================
# OPENSUSE HELPER: adds Packman repo if absent
# yad is not in the official openSUSE repos — requires Packman.
# Automatically detects Tumbleweed vs Leap to build the correct URL.
# =============================================================================
_dc_opensuse_add_packman() {
    # Check if Packman is already configured (any mirror)
    if zypper lr 2>/dev/null | grep -qi packman; then
        _dc_ok "openSUSE: Packman repo already present — skip"
        return 0
    fi

    # Determine version: Tumbleweed or Leap
    local _pm_url=""
    if grep -qi tumbleweed /etc/os-release 2>/dev/null; then
        _pm_url="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/"
    else
        # Leap: extract version (e.g. 15.5)
        local _leap_ver
        _leap_ver=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null \
                    || grep -oP '(?<=VERSION=")[^"]+' /etc/os-release 2>/dev/null \
                    || echo "")
        if [ -n "$_leap_ver" ]; then
            _pm_url="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Leap_${_leap_ver}/"
        else
            _dc_warn "openSUSE: unable to determine version for Packman — skipping"
            return 0
        fi
    fi

    _dc_info "openSUSE: adding Packman repo → $_pm_url"
    zypper ar -cfp 90 "$_pm_url" packman 2>/dev/null || {
        _dc_warn "openSUSE: Packman repo add failed (network unavailable?)"
        return 0
    }
    # Auto-accept GPG keys and update Packman index
    zypper --non-interactive --gpg-auto-import-keys refresh packman 2>/dev/null || true
    _dc_ok "openSUSE: Packman repo added and refreshed"
}

# =============================================================================
# DEPENDENCY INSTALLATION
# Calls the native package manager — same principle as penguins-eggs,
# which always delegates to the host system's package manager
# =============================================================================
dc_install_dependencies() {
    _dc_section "Installing dependencies ($DC_FAMILY / $DC_PKG_MANAGER)"

    if [ "$(id -u)" -ne 0 ]; then
        _dc_error "Installing dependencies requires root privileges"
        exit 1
    fi

    _dc_define_deps
    local -n _DEPS="DC_DEPS_${DC_FAMILY^^}"

    _dc_info "Updating package indexes..."
    eval "$DC_PKG_UPDATE" || {
        _dc_warn "Index update failed, I continue anyway..."
    }

    # ── Family-specific warnings ─────────────────────────────────────────────
    case "$DC_FAMILY" in
        debian)
            # Fix dpkg state from previous builds (clone of clone)
            dpkg --configure -a 2>/dev/null || true
            apt-get install -f -y 2>/dev/null || true
            ;;
        arch)
            _dc_warn "ARCH: 'yad' and 'calamares' may require AUR (yay/paru)"
            _dc_warn "ARCH: live-boot not available → mkinitcpio-archiso will be used"
            _dc_warn "ARCH: generated ISOs will work ONLY on Arch-based systems"
            ;;
        fedora)
            _dc_warn "FEDORA: live-boot not available → dracut-live will be used"
            _dc_warn "FEDORA: generated ISOs will work ONLY on RPM-based systems"
            ;;
        opensuse)
            _dc_warn "OPENSUSE: generated ISOs will work ONLY on openSUSE-based systems"
            # Packman is required for yad (not available in official openSUSE repos).
            # Adds the repo only if not already present.
            _dc_opensuse_add_packman
            ;;
        alpine)
            _dc_warn "ALPINE: experimental support"
            ;;
    esac

    # ── Package installation ─────────────────────────────────────────────────
    _dc_info "Installing: ${_DEPS[*]}"

    local failed_pkgs=()
    for pkg in "${_DEPS[@]}"; do
        _dc_info "  → $pkg"
        if ! eval "$DC_PKG_INSTALL $pkg" >/dev/null 2>&1; then
            _dc_warn "  ✗ $pkg not installed (may not exist on $DC_DISTRO_ID)"
            failed_pkgs+=("$pkg")
        else
            _dc_ok "  ✓ $pkg"
        fi
    done

    # ── Post-install for Debian: force reinstall yad ─────────────────────────
    if [ "$DC_FAMILY" = "debian" ]; then
        apt-get install --reinstall -y yad 2>/dev/null \
            || apt-get install -y yad 2>/dev/null \
            || true
    fi

    if [ ${#failed_pkgs[@]} -gt 0 ]; then
        _dc_warn "Packages not installed: ${failed_pkgs[*]}"
        _dc_warn "Manually check if they are necessary for your system"
    fi

    _dc_ok "Dependency installation complete"
}

# =============================================================================
# SYSTEM INFORMATION SUMMARY
# =============================================================================
dc_print_distro_info() {
    echo ""
    echo -e "${_DC_BOLD}${_DC_BLUE}┌─────────────────────────────────────────┐${_DC_RESET}"
    echo -e "${_DC_BOLD}${_DC_BLUE}│  DistroClone — System detected         │${_DC_RESET}"
    echo -e "${_DC_BOLD}${_DC_BLUE}└─────────────────────────────────────────┘${_DC_RESET}"
    echo -e "  Distro   : ${_DC_BOLD}$DC_DISTRO_PRETTY${_DC_RESET}"
    echo -e "  ID       : $DC_DISTRO_ID"
    echo -e "  Family : ${_DC_BOLD}$DC_FAMILY${_DC_RESET}"
    if [ -n "$DC_CODENAME" ]; then echo -e "  Codename : $DC_CODENAME"; fi
    echo -e "  Pkg mgr  : ${_DC_CYAN}$DC_PKG_MANAGER${_DC_RESET}"
    echo -e "  Kernel   : $(uname -r)"
    echo -e "  Arch     : $(uname -m)"
    if [ -n "${DC_INITRAMFS:-}" ]; then
        echo -e "  Initramfs: ${_DC_CYAN}${DC_INITRAMFS}${_DC_RESET} (kernel: ${DC_KERNEL_FLAVOR:-?})"
        echo -e "  Live stack: ${_DC_CYAN}${DC_LIVE_STACK}${_DC_RESET}"
    fi

    # ISO compatibility notice
    case "$DC_FAMILY" in
        debian)
            echo -e "\n  ${_DC_GREEN}✓ ISO compatible ONLY with Debian-based systems${_DC_RESET}"
            ;;
        arch)
            echo -e "\n  ${_DC_YELLOW}⚠ ISO compatible ONLY with Arch-based systems${_DC_RESET}"
            echo -e "  ${_DC_YELLOW}  (use mkinitcpio instead of live-boot)${_DC_RESET}"
            ;;
        fedora)
            echo -e "\n  ${_DC_YELLOW}⚠ ISO compatible ONLY with RPM-based systems${_DC_RESET}"
            echo -e "  ${_DC_YELLOW}  (use dracut-live instead of live-boot)${_DC_RESET}"
            ;;
        *)
            echo -e "\n  ${_DC_YELLOW}⚠ Family $DC_FAMILY — support exsperimental${_DC_RESET}"
            ;;
    esac
    echo ""
}

# =============================================================================
# SINGLE BOOTSTRAP FUNCTION (recommended entry point)
# Call this at the start of DistroClone.sh instead of the hardcoded apt block
# =============================================================================
dc_bootstrap() {
    dc_detect_distro
    dc_detect_arch_features
    dc_print_distro_info
    dc_check_dependencies || dc_install_dependencies
}

# =============================================================================
# BLOCK TO REPLACE IN DistroClone.sh
# =============================================================================
# BEFORE (hardcoded Debian):
#   dpkg --configure -a 2>/dev/null || true
#   apt-get install -f -y 2>/dev/null || true
#   apt update; apt install -y mtools syslinux-utils isolinux zenity ...
#
# AFTER (cross-distro):
#   source /usr/share/distroClone/distro-detect.sh
#   dc_bootstrap
# =============================================================================
