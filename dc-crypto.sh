#!/bin/bash
# =============================================================================
# dc-crypto.sh — DistroClone Unified Crypto Layer
# Detection + orchestration per LUKS / initramfs / GRUB
# =============================================================================
# USAGE: source dc-crypto.sh && dc_crypto_apply
#
# Funziona in DUE contesti:
#   1. Chroot Calamares (dontChroot: false) — findmnt legge /proc/mounts
#      dell'host → radice target è /tmp/calamares-root, non / → usa fstab
#   2. Sistema live (non chroot) — findmnt funziona normalmente
#
# Variabili esportate dopo _dc_detect_crypto():
#   CRYPTO_TYPE   "luks" | "none"
#   LUKS_UUID     UUID del container LUKS (vuoto se none)
#   MAPPER_NAME   nome del device mapper (es. luks-UUID)
#   ROOT_DEV      device root (es. /dev/mapper/luks-UUID o /dev/sda2)
#   BOOT_DEV      device /boot (vuoto se non separato)
#   DISK_DEV      disco fisico base (es. sda)
#   DC_DISTRO     famiglia distro (fedora|arch|debian|opensuse)
#   DC_DRACUT_DONE flag anti-double-execution per dracut
# =============================================================================

DC_CRYPTO_LOG="${DC_CRYPTO_LOG:-/var/log/dc-crypto.log}"
DC_DRACUT_DONE=0

# Esporta runtime vars (accessibili da dc-initramfs.sh e dc-grub.sh)
CRYPTO_TYPE="none"
LUKS_UUID=""
MAPPER_NAME=""
ROOT_DEV=""
BOOT_DEV=""
DISK_DEV="sda"
DC_DISTRO=""

# =============================================================================
# DISTRO DETECTION
# =============================================================================
_dc_detect_distro() {
    # Priorità: DC_FAMILY (DistroClone) → os-release
    if [ -n "${DC_FAMILY:-}" ]; then
        DC_DISTRO="$DC_FAMILY"
        echo "[DC] DC_DISTRO=$DC_DISTRO (da DC_FAMILY)"
        return
    fi

    local id
    id=$(. /etc/os-release 2>/dev/null; echo "${ID:-linux}")

    case "$id" in
        fedora|centos|rhel|almalinux|rocky) DC_DISTRO="fedora"  ;;
        arch|manjaro|endeavouros|garuda)    DC_DISTRO="arch"    ;;
        debian|ubuntu|linuxmint|pop|kali)   DC_DISTRO="debian"  ;;
        opensuse*|suse*)                    DC_DISTRO="opensuse";;
        *)                                  DC_DISTRO="$id"     ;;
    esac
    echo "[DC] DC_DISTRO=$DC_DISTRO (da /etc/os-release ID=$id)"
}

# =============================================================================
# CHROOT-AWARE ROOT DEVICE
# =============================================================================
# findmnt / nel chroot Calamares restituisce la root del live system (squashfs/loop)
# perché /proc/mounts è quello dell'host dove il target è a /tmp/calamares-root.
# Soluzione: legge /etc/fstab del sistema installato (sempre corretto nel chroot).
_dc_get_root_dev() {
    local from_fstab
    from_fstab=$(awk '$2=="/" && $1!="none" && $1!="tmpfs" {print $1}' \
                 /etc/fstab 2>/dev/null | head -1)

    if [ -n "$from_fstab" ]; then
        echo "$from_fstab"
    else
        # Fallback: script gira su sistema live (non in chroot)
        findmnt -n -o SOURCE / 2>/dev/null
    fi
}

_dc_get_boot_dev() {
    awk '$2=="/boot" && $1!="none" && $1!="tmpfs" {print $1}' \
        /etc/fstab 2>/dev/null | head -1
}

# Ritorna 0 (true) se /boot è cifrato o non è su partizione separata
_dc_boot_is_encrypted() {
    local boot_src
    boot_src=$(_dc_get_boot_dev)
    [ -z "$boot_src" ] && return 0           # nessun /boot separato → root è /boot → LUKS
    [[ "$boot_src" == /dev/mapper/* ]] && return 0  # /boot su LUKS
    return 1                                 # /boot su partizione plain (ext4, etc.)
}

# Ottiene il disco fisico da un device (risale da mapper LUKS se necessario)
_dc_get_disk() {
    local dev="$1"
    local phys="$dev"

    if [[ "$dev" == /dev/mapper/* ]]; then
        phys=$(cryptsetup status "${dev#/dev/mapper/}" 2>/dev/null \
               | awk '/device:/{print $2}' | head -1)
        [ -z "$phys" ] && phys="$dev"
    elif [[ "$dev" == UUID=* ]]; then
        phys=$(blkid -U "${dev#UUID=}" 2>/dev/null) || phys=""
    fi

    local disk
    disk=$(lsblk -no PKNAME "$phys" 2>/dev/null | head -1)
    echo "${disk:-sda}"
}

# =============================================================================
# LUKS DETECTION
# =============================================================================
_dc_detect_crypto() {
    ROOT_DEV=$(_dc_get_root_dev)
    BOOT_DEV=$(_dc_get_boot_dev)
    echo "[DC] ROOT_DEV=$ROOT_DEV"
    echo "[DC] BOOT_DEV=${BOOT_DEV:-<nessuno, root-only>}"

    # ── Detection 1: /dev/mapper/luks-UUID (convenzione Calamares standard) ──
    if [[ "$ROOT_DEV" == /dev/mapper/luks-* ]]; then
        CRYPTO_TYPE="luks"
        MAPPER_NAME="${ROOT_DEV#/dev/mapper/}"
        local phys_dev
        phys_dev=$(cryptsetup status "$MAPPER_NAME" 2>/dev/null \
                   | awk '/device:/{print $2}' | head -1)
        if [ -n "$phys_dev" ]; then
            LUKS_UUID=$(blkid -s UUID -o value "$phys_dev" 2>/dev/null) || LUKS_UUID=""
        fi
        # Fallback UUID dal nome mapper (luks-<UUID>)
        [ -z "$LUKS_UUID" ] && LUKS_UUID="${MAPPER_NAME#luks-}"
        DISK_DEV=$(_dc_get_disk "$ROOT_DEV")
        echo "[DC] CRYPTO_TYPE=luks | MAPPER=$MAPPER_NAME | UUID=$LUKS_UUID | DISK=$DISK_DEV"
        return
    fi

    # ── Detection 2: /etc/crypttab (fstab usa UUID= invece di /dev/mapper/) ──
    if [ -f /etc/crypttab ]; then
        local ct_line
        ct_line=$(grep -v '^#' /etc/crypttab 2>/dev/null \
                  | grep -v '^[[:space:]]*$' | head -1)
        if [ -n "$ct_line" ]; then
            MAPPER_NAME=$(echo "$ct_line" | awk '{print $1}')
            local ct_dev
            ct_dev=$(echo "$ct_line" | awk '{print $2}')
            if [[ "$ct_dev" == UUID=* ]]; then
                LUKS_UUID="${ct_dev#UUID=}"
                CRYPTO_TYPE="luks"
                local phys_dev="/dev/disk/by-uuid/$LUKS_UUID"
                DISK_DEV=$(_dc_get_disk "$(readlink -f "$phys_dev" 2>/dev/null || echo "")")
                echo "[DC] CRYPTO_TYPE=luks (crypttab) | MAPPER=$MAPPER_NAME | UUID=$LUKS_UUID | DISK=$DISK_DEV"
                return
            fi
        fi
    fi

    # ── Detection 3: lsblk TYPE (live system, fallback) ──────────────────────
    # Solo se le detection 1 e 2 falliscono — su live system findmnt funziona
    local live_root
    live_root=$(findmnt -n -o SOURCE / 2>/dev/null)
    if [ -n "$live_root" ] && lsblk -no TYPE "$live_root" 2>/dev/null | grep -q crypt; then
        CRYPTO_TYPE="luks"
        ROOT_DEV="$live_root"
        MAPPER_NAME="${live_root#/dev/mapper/}"
        LUKS_UUID=$(blkid -s UUID -o value "$live_root" 2>/dev/null) || LUKS_UUID=""
        DISK_DEV=$(_dc_get_disk "$live_root")
        echo "[DC] CRYPTO_TYPE=luks (lsblk fallback) | UUID=$LUKS_UUID | DISK=$DISK_DEV"
        return
    fi

    CRYPTO_TYPE="none"
    DISK_DEV=$(_dc_get_disk "$ROOT_DEV")
    [ -z "$DISK_DEV" ] && DISK_DEV="sda"
    echo "[DC] CRYPTO_TYPE=none | ROOT=$ROOT_DEV | DISK=$DISK_DEV"
}

# =============================================================================
# PUBLIC API
# =============================================================================
dc_crypto_apply() {
    echo "════════════════════════════════════════════════════"
    echo "  DistroClone Unified Crypto Layer"
    echo "════════════════════════════════════════════════════"

    _dc_detect_distro
    _dc_detect_crypto

    # Carica backend (stesso directory di dc-crypto.sh)
    local _dc_dir
    _dc_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

    # shellcheck source=dc-initramfs.sh
    source "${_dc_dir}/dc-initramfs.sh"
    # shellcheck source=dc-grub.sh
    source "${_dc_dir}/dc-grub.sh"

    if [ "$CRYPTO_TYPE" = "luks" ]; then
        echo "[DC] Applying full LUKS stack (distro=$DC_DISTRO uuid=$LUKS_UUID)..."
        dc_configure_grub_params
        dc_configure_initramfs
        dc_configure_btrfs_rootflags
        dc_install_grub
    else
        echo "[DC] Nessuna cifratura rilevata — solo grub-install/mkconfig"
        dc_configure_btrfs_rootflags
        dc_install_grub
    fi

    echo "[DC] ✓ Crypto layer completato"
}
