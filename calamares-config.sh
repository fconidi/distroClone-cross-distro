#!/bin/bash
# =============================================================================
# calamares-config.sh — DistroClone Calamares configurator (chroot-side)
# =============================================================================
# Genera tutta la configurazione Calamares adatta alla famiglia distro corrente.
# Questo script viene copiato in $DEST/tmp/ e chiamato DALL'INTERNO del chroot.
#
# Inspired by penguins-eggs/src/classes/incubation/incubator.ts (MIT)
# Adapted for DistroClone by Franco Conidi aka edmond
#
# Uso (dal chroot):
#   bash /tmp/calamares-config.sh <family> <distro_id> <branding_id>
#
# Argomenti:
#   $1 = DC_FAMILY    : debian | arch | fedora | opensuse | alpine
#   $2 = DC_DISTRO_ID : debian | ubuntu | arch | fedora | ...
#   $3 = BRANDING_ID  : nome per /usr/share/calamares/branding/<id>
# =============================================================================

set +e   # Permetti fallimenti non critici; dc_settings_conf() deve SEMPRE girare

DC_FAMILY="${1:-debian}"
DC_DISTRO_ID="${2:-debian}"
BRANDING_ID="${3:-distroClone}"

# Leggi password live — scritta da DistroClone.sh in $DEST/tmp/dc_env.sh
# Usata come fallback se Calamares users module non imposta la password
_DC_FALLBACK_PWD="distroClone1!"
[ -f /tmp/dc_env.sh ] && . /tmp/dc_env.sh
_DC_FALLBACK_PWD="${DC_ROOT_PASSWORD:-distroClone1!}"

# Determina live user per famiglia (usato in exclude unpackfs)
_DC_LIVE_USER=$(cat /etc/distroClone-live-user 2>/dev/null | tr -d '[:space:]')
if [ -z "$_DC_LIVE_USER" ]; then
    case "$DC_FAMILY" in
        debian)   _DC_LIVE_USER="admin" ;;
        fedora)   _DC_LIVE_USER="liveuser" ;;
        arch)     _DC_LIVE_USER="archie" ;;
        opensuse) _DC_LIVE_USER="linux" ;;
        *)        _DC_LIVE_USER="admin" ;;
    esac
fi

SETTINGS_FILE="/etc/calamares/settings.conf"

echo "══════════════════════════════════════════════════════"
echo "  DistroClone — Calamares config [$DC_FAMILY]"
echo "══════════════════════════════════════════════════════"

# -----------------------------------------------------------------------------
# Helper YAML
# -----------------------------------------------------------------------------
yaml_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_shellprocess_conf() {
    local outfile="$1"
    local dont_chroot="$2"
    local timeout="$3"
    shift 3

    {
        echo "---"
        echo "dontChroot: ${dont_chroot}"
        echo "timeout: ${timeout}"
        echo "script:"
        local cmd
        for cmd in "$@"; do
            printf '  - "%s"\n' "$(yaml_escape "$cmd")"
        done
    } > "${outfile}"
}

settings_add_instance() {
    local id="$1"
    local conf="$2"
    {
        echo
        printf '  - id: %s\n' "${id}"
        echo '    module: shellprocess'
        printf '    config: %s\n' "${conf}"
    } >> "${SETTINGS_FILE}"
}

settings_exec_add() {
    printf '      - %s\n' "$1" >> "${SETTINGS_FILE}"
}

settings_begin() {
    {
        echo "---"
        printf 'modules-search: [ local, %s ]\n' "${CAL_MODULES}"
        echo
        echo "instances:"
        echo "  - id: grubinstall"
        echo "    module: shellprocess"
        echo "    config: grubinstall.conf"
        echo
        echo "  - id: remove-live-user"
        echo "    module: shellprocess"
        echo "    config: remove-live-user.conf"
    } > "${SETTINGS_FILE}"
}

settings_begin_sequence() {
    cat >> "${SETTINGS_FILE}" <<'EOF'

sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
      - users
      - summary

  - exec:
      - partition
      - mount
      - unpackfs
      - shellprocess@remove-live-user
      - machineid
      - fstab
      - locale
      - keyboard
EOF
}

settings_finish() {
    cat >> "${SETTINGS_FILE}" <<EOF

  - show:
      - finished

branding: ${BRANDING_ID}
prompt-install: true
dont-chroot: false
disable-cancel: false
disable-cancel-during-exec: false
quit-at-end: false

# NOTA: "globalStorage:" NON è supportato da Calamares 3.2.x (Settings.cpp lo ignora).
# Per openSUSE, rootMountPoint è impostato dal modulo Python "setrootmount" nella
# exec sequence (primo step). Questo blocco è mantenuto per compatibilità futura
# con Calamares 3.3.x che potrebbe supportarlo.
globalStorage:
  rootMountPoint: "/tmp/calamares-root"
EOF
}

# -----------------------------------------------------------------------------
# Source modulo famiglia
# -----------------------------------------------------------------------------
_DC_MODFILE="/tmp/calamares-config-${DC_FAMILY}.sh"

# Fallback: opensuse usa il modulo fedora (stessa struttura)
if [ "$DC_FAMILY" = "opensuse" ] && [ ! -f "$_DC_MODFILE" ]; then
    _DC_MODFILE="/tmp/calamares-config-fedora.sh"
fi

# Fallback finale: debian (per famiglie non mappate)
if [ ! -f "$_DC_MODFILE" ]; then
    echo "[WARN] Modulo famiglia non trovato: /tmp/calamares-config-${DC_FAMILY}.sh"
    _DC_MODFILE="/tmp/calamares-config-debian.sh"
fi

if ! . "$_DC_MODFILE" 2>/dev/null; then
    echo "[ERROR] Impossibile caricare il modulo famiglia: $_DC_MODFILE" >&2
    exit 1
fi

echo "  Modulo famiglia: $_DC_MODFILE"

# Imposta percorsi specifici famiglia (funzione definita nel modulo)
dc_set_paths

echo "  PKG backend   : $PKG_BACKEND"
echo "  Moduli CAL    : $CAL_MODULES"
echo "  GRUB cmd      : $GRUB_CMD"
echo "  Squashfs path : $SQUASHFS_PATH"

# -----------------------------------------------------------------------------
# Setup directory
# -----------------------------------------------------------------------------
mkdir -p /etc/calamares/modules
mkdir -p /etc/calamares/modules-backup
cp -r /etc/calamares/modules/*.conf /etc/calamares/modules-backup/ 2>/dev/null || true

# =============================================================================
# 1. UNPACKFS
# =============================================================================
echo "[1/9] unpackfs.conf → $SQUASHFS_PATH"
cat > /etc/calamares/modules/unpackfs.conf << UNPACK
---
unpack:
  - source: "${SQUASHFS_PATH}"
    sourcefs: "squashfs"
    destination: ""
    exclude:
      - /dev/*
      - /proc/*
      - /sys/*
      - /run/*
      - /tmp/*
      - /mnt/*
      - /media/*
      - /lost+found
      - /var/cache/apt/archives/*
      - /var/lib/apt/lists/*
      - /var/lib/pacman/sync/*
      - /var/cache/pacman/pkg/*
      - /var/log/*
      - /var/tmp/*
      - /swapfile
      - /home/${_DC_LIVE_USER}/*
UNPACK

# =============================================================================
# 2. MOUNT
# =============================================================================
echo "[2/9] mount.conf"
cat > /etc/calamares/modules/mount.conf << 'MOUNT'
---
extraMounts:
  - device: proc
    fs: proc
    mountPoint: /proc
  - device: sys
    fs: sysfs
    mountPoint: /sys
  - device: /dev
    mountPoint: /dev
    options: [ "bind" ]
  - device: /dev/pts
    mountPoint: /dev/pts
    options: [ "bind" ]
  - device: tmpfs
    fs: tmpfs
    mountPoint: /run
  - device: /run/udev
    mountPoint: /run/udev
    options: [ "bind" ]

extraMountsEfi:
  - device: efivarfs
    fs: efivarfs
    mountPoint: /sys/firmware/efi/efivars
MOUNT

# =============================================================================
# 3. FSTAB
# =============================================================================
echo "[3/9] fstab.conf"
cat > /etc/calamares/modules/fstab.conf << 'FSTAB_CONF'
---
mountOptions:
  default: defaults,noatime
  btrfs: defaults,noatime,compress=zstd
  ext4: defaults,noatime
  xfs: defaults,noatime

ssdExtraMountOptions:
  ext4: discard
  xfs: discard

crypttab: true
crypttabOptions: luks,discard
FSTAB_CONF

# =============================================================================
# 4. USERS — delegato al modulo famiglia
# =============================================================================
echo "[4/9] users.conf"
dc_users_conf

# =============================================================================
# 5. PARTITION
# =============================================================================
echo "[5/9] partition.conf"
# defaultFileSystemType: detect root filesystem of the running source system.
# Propagating source FS to target default avoids subvolume/feature loss on
# btrfs-native distros (Garuda, CachyOS, openSUSE). User can still change via
# the Calamares dropdown — partitionLayout must NOT hardcode `filesystem:`
# (that would override the UI selection and always create ext4).
_DC_DEFAULT_FS="ext4"
_DC_SRC_ROOT_FS=$(findmnt -no FSTYPE / 2>/dev/null | head -1)
case "${_DC_SRC_ROOT_FS:-}" in
    btrfs|xfs|ext4) _DC_DEFAULT_FS="$_DC_SRC_ROOT_FS" ;;
esac
# Hardcoded fallback (kept for safety if findmnt detection fails on minimal live envs)
[ "$DC_FAMILY"    = "opensuse" ] && [ "$_DC_DEFAULT_FS" = "ext4" ] && _DC_DEFAULT_FS="btrfs"
[ "$DC_DISTRO_ID" = "garuda"   ] && [ "$_DC_DEFAULT_FS" = "ext4" ] && _DC_DEFAULT_FS="btrfs"
[ "$DC_DISTRO_ID" = "cachyos"  ] && [ "$_DC_DEFAULT_FS" = "ext4" ] && _DC_DEFAULT_FS="btrfs"
echo "[DC] partition.conf: defaultFileSystemType=$_DC_DEFAULT_FS (source / = ${_DC_SRC_ROOT_FS:-unknown})"
# Garuda: 512M per ospitare linux-zen + fallback initramfs + futuri snapshot grub-btrfs
_DC_EFI_SIZE="300M"
[ "$DC_DISTRO_ID" = "garuda" ] && _DC_EFI_SIZE="512M"
cat > /etc/calamares/modules/partition.conf << PARTCONF
---
efiSystemPartition: "/boot/efi"
efiSystemPartitionSize: ${_DC_EFI_SIZE}
efiSystemPartitionName: EFI

drawNestedPartitions: true
alwaysShowPartitionLabels: true

enabledPartitionChoices:
  - erase
  - replace
  - manual

enabledEncryptionTypes:
  - luks

userSwapChoices:
  - none
  - small
  - file

initialPartitioningChoice: erase
initialSwapChoice: none

defaultFileSystemType: "${_DC_DEFAULT_FS}"
availableFileSystemTypes: [ "ext4", "btrfs", "xfs" ]

partitionLayout:
  - name: "rootfs"
    filesystem: "${_DC_DEFAULT_FS}"
    mountPoint: "/"
    size: 100%
    minSize: 8G
PARTCONF
# NOTE: `filesystem:` IS required — omitting it makes Calamares create the
# partition as "unformatted". The value comes from source `/` detection
# (findmnt) which propagates the clone's filesystem to the target.
# The UI dropdown will NOT override this value; users wanting a different
# filesystem must either (a) rebuild DistroClone on a differently-formatted
# source, or (b) use Manual partitioning in Calamares.

# =============================================================================
# 6. PACKAGES
# =============================================================================
echo "[6/9] packages.conf → backend: $PKG_BACKEND"
cat > /etc/calamares/modules/packages.conf << PACKAGES
---
backend: ${PKG_BACKEND}
operations: []
skip_if_no_internet: false
update_db: false
update_system: false
PACKAGES

# =============================================================================
# 7. DISPLAYMANAGER + FINISHED
# =============================================================================
echo "[7/9] displaymanager.conf + finished.conf"
cat > /etc/calamares/modules/displaymanager.conf << 'DMCONF'
---
displaymanagers:
  - lightdm
  - sddm
  - gdm
  - slim
basicSetup: false
DMCONF

cat > /etc/calamares/modules/finished.conf << 'FINCONF'
---
restartNowEnabled: true
restartNowChecked: true
restartNowCommand: "systemctl reboot"
notifyOnFinished: true
FINCONF

# welcome.conf — lingua UI Calamares: en_US.UTF-8, GeoIP disabilitato
# defaultLocale: pre-seleziona inglese nella schermata di benvenuto
# geoip style:none: evita timeout rete nel live system
cat > /etc/calamares/modules/welcome.conf << 'WELCOME_CONF'
---
# DistroClone: Calamares welcome module
defaultLocale: "en_US.UTF-8"

geoip:
    style: "none"

requirements:
    requiredStorage: 5
    requiredRam: 2
    internetCheckUrl: "http://example.com"
    check:
        # storage ESCLUSO: Calamares misura il live squashfs (sempre 0 byte
        # liberi, read-only) invece del disco fisico target → falso negativo.
        # La verifica reale avviene in disk-setup (o nel modulo partition).
        - ram
        - power
    required:
        - ram
WELCOME_CONF
echo "[DC] ✓ welcome.conf: defaultLocale=en_US.UTF-8, GeoIP disabilitato"

# =============================================================================
# 8. UNIFIED CRYPTO LAYER — genera moduli inline (autocontenuto)
# I moduli sono generati direttamente: zero dipendenze da file esterni,
# funziona con qualsiasi versione AppImage senza rebuild.
# =============================================================================
echo "[8/9] Generazione dc-crypto layer → /usr/local/lib/distroClone/"
mkdir -p /usr/local/lib/distroClone

# ── dc-crypto.sh ─────────────────────────────────────────────────────────────
cat > /usr/local/lib/distroClone/dc-crypto.sh << 'DCCRYPTO'
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
        dc_defrag_boot_files_btrfs
        dc_install_grub
    else
        echo "[DC] Nessuna cifratura rilevata — solo grub-install/mkconfig"
        dc_configure_btrfs_rootflags
        dc_defrag_boot_files_btrfs
        dc_install_grub
    fi

    echo "[DC] ✓ Crypto layer completato"
}
DCCRYPTO

# ── dc-initramfs.sh ──────────────────────────────────────────────────────────
cat > /usr/local/lib/distroClone/dc-initramfs.sh << 'DCINITRAMFS'
#!/bin/bash
# =============================================================================
# dc-initramfs.sh — DistroClone initramfs backends
# =============================================================================
# Sourced da dc-crypto.sh. Richiede: DC_DISTRO, LUKS_UUID, DC_DRACUT_DONE
# =============================================================================

dc_configure_initramfs() {
    echo "[DC] Configuring initramfs (distro=$DC_DISTRO)..."

    case "$DC_DISTRO" in
        arch)              _dc_initramfs_arch    ;;
        fedora|opensuse)   _dc_initramfs_dracut  ;;
        debian|ubuntu)     _dc_initramfs_debian  ;;
        *)
            echo "[DC] WARN: distro '$DC_DISTRO' sconosciuta — auto-detect initramfs tool"
            if   command -v dracut          >/dev/null 2>&1; then _dc_initramfs_dracut
            elif command -v mkinitcpio      >/dev/null 2>&1; then _dc_initramfs_arch
            elif command -v update-initramfs>/dev/null 2>&1; then _dc_initramfs_debian
            else echo "[DC] WARN: nessun initramfs tool trovato — skip"
            fi
            ;;
    esac
}

# =============================================================================
# ARCH — mkinitcpio
# =============================================================================
_dc_initramfs_arch() {
    local mc="/etc/mkinitcpio.conf"
    [ -f "$mc" ] || { echo "[DC] WARN: $mc non trovato — skip"; return; }

    local cur_hooks
    cur_hooks=$(grep '^HOOKS=' "$mc")
    echo "[DC] Arch HOOKS attuali: $cur_hooks"

    # Aggiunge 'encrypt' dopo 'block' se mancante
    if ! echo "$cur_hooks" | grep -q '\bencrypt\b'; then
        sed -i 's/\( block\)\( \)/\1 encrypt\2/' "$mc"
        # fallback se pattern non matcha
        grep -q '\bencrypt\b' "$mc" || \
            sed -i 's/ block / block encrypt /' "$mc"
    fi

    # Riposiziona 'keyboard' immediatamente prima di 'encrypt'
    cur_hooks=$(grep '^HOOKS=' "$mc")
    if echo "$cur_hooks" | grep -q '\bkeyboard\b'; then
        local no_kb new_hooks
        no_kb=$(echo "$cur_hooks" | sed 's/ keyboard//')
        new_hooks=$(echo "$no_kb" | sed 's/ block encrypt / block keyboard encrypt /')
        sed -i "s|^HOOKS=.*|${new_hooks}|" "$mc"
    fi

    echo "[DC] Arch HOOKS aggiornati: $(grep '^HOOKS=' "$mc")"

    echo "[DC] Eseguo mkinitcpio -P..."
    if ! mkinitcpio -P 2>&1; then
        echo "[DC] ERROR: mkinitcpio -P fallito — installazione LUKS non completata"
        return 1
    fi
    echo "[DC] ✓ mkinitcpio -P completato"
}

# =============================================================================
# FEDORA / openSUSE — dracut
# =============================================================================
_dc_initramfs_dracut() {
    if [ "${DC_DRACUT_DONE:-0}" -eq 1 ]; then
        echo "[DC] dracut già eseguito — skip"
        return
    fi

    # Config persistente: garantisce modulo crypt anche dopo aggiornamenti kernel
    mkdir -p /etc/dracut.conf.d
    cat > /etc/dracut.conf.d/10-dc-luks.conf << 'DRACUTCFG'
add_dracutmodules+=" crypt "
install_items+=" /etc/crypttab cryptsetup "
DRACUTCFG
    echo "[DC] ✓ /etc/dracut.conf.d/10-dc-luks.conf"

    local kver
    kver=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)
    if [ -z "$kver" ]; then
        echo "[DC] WARN: nessun kernel in /lib/modules — dracut skip"
        return
    fi

    # /var/tmp richiesto da dracut in alcuni ambienti chroot
    mkdir -p /var/tmp

    echo "[DC] dracut --hostonly --add crypt kver=$kver ..."
    # --hostonly: CORRETTO nel chroot Calamares (il sistema installato ha LUKS
    #   attivo → dracut lo rileva e include crypt). 10× più veloce di --no-hostonly.
    # --add "crypt": garanzia esplicita se la detection automatica fallisce.
    # NON usare --no-hostonly: scansiona tutto l'hw → 10-20 min in VM → timeout.
    if dracut --force --hostonly --add "crypt" \
        "/boot/initramfs-${kver}.img" "$kver" 2>&1; then
        echo "[DC] ✓ dracut completato — initramfs-${kver}.img"
    else
        echo "[DC] WARN: dracut exit non-zero (potrebbe essere non critico)"
    fi

    DC_DRACUT_DONE=1
}

# =============================================================================
# DEBIAN / UBUNTU — update-initramfs
# =============================================================================
_dc_initramfs_debian() {
    mkdir -p /etc/cryptsetup-initramfs
    # Idempotente: rimuovi prima di aggiungere
    grep -qx 'CRYPTSETUP=y' /etc/cryptsetup-initramfs/conf-hook 2>/dev/null || \
        echo "CRYPTSETUP=y" >> /etc/cryptsetup-initramfs/conf-hook

    mkdir -p /etc/initramfs-tools/conf.d
    echo "CRYPTSETUP=y" > /etc/initramfs-tools/conf.d/cryptsetup

    # Moduli kernel dm-crypt (idempotente — aggiunge solo se mancanti)
    local mf="/etc/initramfs-tools/modules"
    for mod in dm-crypt dm-mod aes aes_generic sha256 sha256_generic cbc xts algif_skcipher; do
        grep -qx "$mod" "$mf" 2>/dev/null || echo "$mod" >> "$mf"
    done

    echo "[DC] Eseguo update-initramfs -u -k all ..."
    if update-initramfs -u -k all 2>&1; then
        echo "[DC] ✓ update-initramfs completato"
    else
        echo "[DC] WARN: update-initramfs exit non-zero"
    fi
}
DCINITRAMFS

# ── dc-grub.sh ───────────────────────────────────────────────────────────────
cat > /usr/local/lib/distroClone/dc-grub.sh << 'DCGRUB'
#!/bin/bash
# =============================================================================
# dc-grub.sh — DistroClone Unified GRUB Layer
# =============================================================================
# Sourced da dc-crypto.sh. Richiede: DC_DISTRO, CRYPTO_TYPE, LUKS_UUID,
#   MAPPER_NAME, DISK_DEV, ROOT_DEV, BOOT_DEV
# Funzioni:
#   dc_configure_grub_params   — LUKS params in /etc/default/grub + cmdline
#   dc_install_grub            — grub-install + grub-mkconfig
# =============================================================================

# =============================================================================
# BTRFS rootflags=subvol=@ → /etc/default/grub + /etc/kernel/cmdline + BLS
# =============================================================================
# Senza rootflags=subvol=@, dracut monta il top-level btrfs come /sysroot
# che è vuoto (l'OS è nel subvolume @) → "does not seem to be an OS tree".
dc_configure_btrfs_rootflags() {
    # Rileva se root è btrfs con subvolume @
    local _root_fs=""
    _root_fs=$(awk '$2=="/" && $1!="none" {print $3}' /etc/fstab 2>/dev/null | head -1)
    [ "$_root_fs" != "btrfs" ] && return 0

    # Controlla se subvolume @ esiste (verifica nel filesystem montato)
    if ! btrfs subvolume list / 2>/dev/null | grep -qE '(^|\s)path @$'; then
        echo "[DC] btrfs senza subvolume @ — rootflags non necessario"
        return 0
    fi

    echo "[DC] btrfs con subvolume @ rilevato — inietto rootflags=subvol=@"
    local _rf="rootflags=subvol=@"

    # ── Imposta @ come default subvolume btrfs ──────────────────────────────
    # Senza questa operazione grub-probe genera path /@/boot/vmlinuz-* (relativo
    # al top-level). Alcuni driver btrfs di GRUB non navigano correttamente nei
    # subvolumi dall'alto e leggono il directory-entry @  come file regolare →
    # "premature end of file /®/boot/vmlinuz-linux-zen".
    # Con default-subvol = @ , grub-probe genera /boot/vmlinuz-* e GRUB apre
    # il btrfs direttamente nel subvolume @, trovando il kernel senza prefisso /@.
    #
    # Eccezione Garuda/CachyOS: GRUB btrfs driver (2.14) non naviga subvolume
    # default correttamente. Con set-default=@ + path /boot/vmlinuz senza /@/,
    # il driver fallisce con "file /boot/vmlinuz-* not found" (CachyOS) o
    # "fs/btrfs: not found" (Garuda, core.img prefix resolution con /@/@/...).
    # Soluzione: lasciare default=5 (top-level) + paths /@/ espliciti in grub.cfg.
    # Questo è il comportamento nativo Garuda, e per CachyOS viene gestito dal
    # fix inject /@/ in dc-grub.sh (se grub-mkconfig genera path senza /@/).
    # Osservato su hardware reale Garuda 2026-04-20 + VM CachyOS 2026-04-20.
    local _distro_id=""
    _distro_id=$(. /etc/os-release 2>/dev/null; echo "${ID:-}${ID_LIKE:+ }${ID_LIKE:-}")
    if echo "$_distro_id" | grep -qiE '(^|\s)(garuda|cachyos)(\s|$)'; then
        echo "[DC] ${_distro_id} — skip set-default @ (GRUB btrfs driver needs default=5)"
    else
        local _at_id
        _at_id=$(btrfs subvolume list / 2>/dev/null | awk '/path @$/{print $2}' | head -1)
        if [ -n "$_at_id" ]; then
            btrfs subvolume set-default "$_at_id" / 2>/dev/null \
                && echo "[DC] ✓ btrfs default subvol → @ (ID=$_at_id)" \
                || echo "[DC] WARN: set-default fallito — grub.cfg potrebbe avere path /@/"
        fi
    fi

    # ── GRUB_CMDLINE_LINUX: aggiungi rootflags se non presente ─────────────
    if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub 2>/dev/null; then
        if ! grep -q 'rootflags=subvol=@' /etc/default/grub 2>/dev/null; then
            sed -i "s|^\(GRUB_CMDLINE_LINUX=\".*\)\"|\1 ${_rf}\"|" /etc/default/grub
            echo "[DC] ✓ rootflags=subvol=@ aggiunto a GRUB_CMDLINE_LINUX"
        fi
    else
        echo "GRUB_CMDLINE_LINUX=\"${_rf}\"" >> /etc/default/grub
        echo "[DC] ✓ GRUB_CMDLINE_LINUX=\"${_rf}\" (nuovo)"
    fi

    # ── /etc/kernel/cmdline (BLS per Fedora/openSUSE) ──────────────────────
    if [ "$DC_DISTRO" = "fedora" ] || [ "$DC_DISTRO" = "opensuse" ]; then
        mkdir -p /etc/kernel
        if [ -f /etc/kernel/cmdline ]; then
            if ! grep -q 'rootflags=subvol=@' /etc/kernel/cmdline 2>/dev/null; then
                sed -i "s|$| ${_rf}|" /etc/kernel/cmdline
                echo "[DC] ✓ rootflags=subvol=@ aggiunto a /etc/kernel/cmdline"
            fi
        else
            local _root_uuid
            _root_uuid=$(awk '$2=="/" {print $1}' /etc/fstab 2>/dev/null | sed 's|UUID=||' | head -1)
            echo "root=UUID=${_root_uuid} ro quiet ${_rf}" > /etc/kernel/cmdline
            echo "[DC] ✓ /etc/kernel/cmdline creato con rootflags"
        fi
    fi

    # ── BLS entries: inietta rootflags nelle options ────────────────────────
    local _bls_dir="/boot/loader/entries"
    if [ -d "$_bls_dir" ]; then
        local _entry
        for _entry in "${_bls_dir}"/*.conf; do
            [ -f "$_entry" ] || continue
            if ! grep -q 'rootflags=subvol=@' "$_entry" 2>/dev/null; then
                sed -i "s|^options .*|& ${_rf}|" "$_entry"
                echo "[DC] ✓ BLS rootflags: $(basename "$_entry")"
            fi
        done
    fi

    echo "[DC] ✓ rootflags=subvol=@ configurato"
}

# =============================================================================
# LUKS PARAMS → /etc/default/grub + /etc/kernel/cmdline
# =============================================================================
dc_configure_grub_params() {
    [ "$CRYPTO_TYPE" != "luks" ] && return
    echo "[DC] Configurazione parametri GRUB per LUKS (UUID=$LUKS_UUID)..."

    # ── crypttab (idempotente) ────────────────────────────────────────────────
    if [ -n "$MAPPER_NAME" ] && [ -n "$LUKS_UUID" ]; then
        sed -i "/^${MAPPER_NAME}/d" /etc/crypttab 2>/dev/null || true
        echo "${MAPPER_NAME} UUID=${LUKS_UUID} none luks,discard" >> /etc/crypttab
        echo "[DC] ✓ crypttab: $MAPPER_NAME UUID=$LUKS_UUID none luks,discard"
    fi

    # ── GRUB_CMDLINE_LINUX ────────────────────────────────────────────────────
    # Arch/mkinitcpio → hook 'encrypt' richiede cryptdevice= (ignora rd.luks.uuid=)
    # Fedora/openSUSE → dracut/systemd usa rd.luks.uuid=
    local cmdline
    if [ "$DC_DISTRO" = "arch" ] || \
       ([ "$DC_DISTRO" != "fedora" ] && [ "$DC_DISTRO" != "opensuse" ] && \
        command -v mkinitcpio >/dev/null 2>&1); then
        local _map="${MAPPER_NAME:-luks-${LUKS_UUID}}"
        cmdline="cryptdevice=UUID=${LUKS_UUID}:${_map} root=/dev/mapper/${_map}"
        echo "[DC] Arch/mkinitcpio → cryptdevice=UUID=${LUKS_UUID}:${_map}"
    else
        cmdline="rd.luks.uuid=${LUKS_UUID}"
        echo "[DC] dracut/systemd → rd.luks.uuid=${LUKS_UUID}"
    fi
    sed -i '/^GRUB_CMDLINE_LINUX=/d' /etc/default/grub 2>/dev/null || true
    echo "GRUB_CMDLINE_LINUX=\"${cmdline}\"" >> /etc/default/grub
    echo "[DC] ✓ GRUB_CMDLINE_LINUX=\"${cmdline}\""

    # ── /etc/kernel/cmdline (Fedora/openSUSE BLS) ─────────────────────────────
    # dracut e grub2-mkconfig usano questo file per i parametri kernel BLS.
    # Garantisce che aggiornamenti kernel futuri mantengano rd.luks.uuid.
    if [ "$DC_DISTRO" = "fedora" ] || [ "$DC_DISTRO" = "opensuse" ]; then
        echo "[DC] Configuring /etc/kernel/cmdline for LUKS (BLS)..."
        mkdir -p /etc/kernel
        sed -i '/rd\.luks\.uuid=/d' /etc/kernel/cmdline 2>/dev/null || true
        echo "${cmdline} rd.lvm=1" >> /etc/kernel/cmdline
        echo "[DC] ✓ /etc/kernel/cmdline: ${cmdline} rd.lvm=1"
    fi

    # ── GRUB_ENABLE_CRYPTODISK ────────────────────────────────────────────────
    # Solo se /boot è cifrato o non è su partizione separata.
    # Con /boot su ext4 NON cifrato (Fedora standard, layout DistroClone):
    #   GRUB legge kernel/initramfs senza passare per LUKS → NO cryptodisk.
    #   Impostarlo inutilmente causa: PBKDF2 software in GRUB (30-60s, no AES-NI)
    #   + doppio prompt password (GRUB + dracut/systemd).
    sed -i '/^GRUB_ENABLE_CRYPTODISK=/d' /etc/default/grub 2>/dev/null || true
    if _dc_boot_is_encrypted; then
        echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
        echo "[DC] ✓ GRUB_ENABLE_CRYPTODISK=y (/boot cifrato o non separato)"
    else
        echo "[DC] GRUB_ENABLE_CRYPTODISK NON impostato (/boot su partizione non cifrata)"
    fi

    # ── Fedora/openSUSE: aggiorna BLS entries con parametri LUKS ────────────
    # NON disabilitare GRUB_ENABLE_BLSCFG — grub2-mkconfig Fedora usa BLS per
    # trovare i kernel; senza BLS il menu GRUB risulta vuoto (solo UEFI entry).
    # Invece: inietta rd.luks.uuid= nelle options dei BLS entries esistenti.
    if [ "$DC_DISTRO" = "fedora" ] || [ "$DC_DISTRO" = "opensuse" ]; then
        local _bls_dir="/boot/loader/entries"
        if [ -d "$_bls_dir" ]; then
            local _entry _count=0
            for _entry in "${_bls_dir}"/*.conf; do
                [ -f "$_entry" ] || continue
                # Aggiungi rd.luks.uuid= se non già presente
                if ! grep -q "rd\.luks\.uuid=${LUKS_UUID}" "$_entry" 2>/dev/null; then
                    sed -i "s|^options .*|& rd.luks.uuid=${LUKS_UUID}|" "$_entry"
                    echo "[DC] ✓ BLS entry aggiornata: $(basename "$_entry")"
                    _count=$((_count + 1))
                fi
            done
            [ "$_count" -eq 0 ] && echo "[DC] WARN: nessun BLS entry trovato/aggiornato in $_bls_dir"
        else
            echo "[DC] WARN: $_bls_dir non trovato — BLS entries non aggiornate"
        fi
    fi

    # ── Rimuovi parametri live ────────────────────────────────────────────────
    for _pat in 'archisobasedir=[^ "]*' 'archisolabel=[^ "]*' 'copytoram[^ "]*' \
                'rd\.live\.[^ "]*' 'root=live:[^ "]*' 'boot=live[^ "]*' \
                'live-config[^ "]*' 'live-media[^ "]*'; do
        sed -i "s/ ${_pat}//g" /etc/default/grub 2>/dev/null || true
    done
    sed -i 's/  */ /g; s/=" /="/g; s/ "/"/' /etc/default/grub 2>/dev/null || true

    echo "[DC] /etc/default/grub (riepilogo):"
    grep -E 'GRUB_CMDLINE|GRUB_ENABLE_CRYPTODISK|GRUB_ENABLE_BLSCFG' \
        /etc/default/grub 2>/dev/null | head -6 || true
}

# =============================================================================
# grub.cfg DIRETTO (bypass grub2-mkconfig per partizione /boot separata)
# =============================================================================
# Problema: dentro il chroot Calamares, /proc/mounts (anche con proc fresco)
# mostra i mount point HOST (/tmp/calamares-root/boot), non quelli del chroot.
# grub2-probe --target=device /boot non riesce a matchare il path chroot →
# fallback alla partizione root → search --set=root --fs-uuid ROOT_UUID →
# GRUB cerca linux /vmlinuz-xxx sulla partizione root → "file not found".
# Soluzione: scrivere grub.cfg direttamente con UUID corretti da /etc/fstab.
# Usato solo con grub2 + /boot su partizione separata (openSUSE, Fedora layout DC).
# grub-mkconfig (Debian/Arch) non ha questo problema → usato as-is.
_dc_write_grub_cfg_direct() {
    local grub_cfg="$1"

    # UUID da fstab (scritto da dc-write-fstab.sh con UUID reali del disco target)
    local _root_uuid _boot_uuid
    _root_uuid=$(awk '$2=="/" {print $1}' /etc/fstab 2>/dev/null | sed 's|UUID=||')
    _boot_uuid=$(awk '$2=="/boot" {print $1}' /etc/fstab 2>/dev/null | sed 's|UUID=||')

    local _kver
    _kver=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)

    local _title
    _title=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")

    # Diagnostica: lista /boot/ e /lib/modules/ per debug
    echo "[DC] /boot/: $(ls /boot/ 2>/dev/null | tr '\n' ' ')"
    echo "[DC] /lib/modules/: $(ls /lib/modules/ 2>/dev/null | tr '\n' ' ')"

    # Cerca kernel — usa solo file verificati su disco
    local _vmlinuz="" _initrd=""
    for _vf in "/boot/vmlinuz-${_kver}" "/boot/vmlinuz"; do
        [ -f "$_vf" ] && { _vmlinuz="$_vf"; break; }
    done
    # Glob fallback: cerca qualsiasi vmlinuz in /boot/
    if [ -z "$_vmlinuz" ]; then
        _vmlinuz=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
        [ -n "$_vmlinuz" ] && echo "[DC] vmlinuz trovato via glob: $_vmlinuz"
    fi

    for _if in "/boot/initramfs-${_kver}.img" \
               "/boot/initrd-${_kver}"        \
               "/boot/initrd"; do
        [ -f "$_if" ] && { _initrd="$_if"; break; }
    done
    # Glob fallback initrd
    if [ -z "$_initrd" ]; then
        _initrd=$(ls /boot/initramfs-*.img /boot/initrd-* 2>/dev/null | sort -V | tail -1)
        [ -n "$_initrd" ] && echo "[DC] initrd trovato via glob: $_initrd"
    fi

    echo "[DC] grub.cfg diretto:"
    echo "[DC]   root UUID : ${_root_uuid:-MANCANTE}"
    echo "[DC]   boot UUID : ${_boot_uuid:-uguale a root}"
    echo "[DC]   vmlinuz   : ${_vmlinuz:-MANCANTE}"
    echo "[DC]   initrd    : ${_initrd:-nessuno}"

    if [ -z "$_root_uuid" ]; then
        echo "[DC] ERROR: root_uuid mancante da fstab — impossibile scrivere grub.cfg"
        return 1
    fi
    if [ -z "$_vmlinuz" ]; then
        echo "[DC] WARN: vmlinuz non trovato in /boot — grub.cfg non scritto"
        return 1
    fi

    # Se /boot è partizione separata: $root = boot partition, paths senza /boot/
    # Se /boot è sulla root:          $root = root partition, paths con /boot/
    # IMPORTANTE: NON fidarsi solo di fstab — verificare che /boot sia un VERO
    # mountpoint. Il fstab potrebbe avere /boot ereditato dal sistema sorgente
    # anche se il layout target ha solo EFI + root (senza /boot separata).
    local _grub_root_uuid _path_prefix _boot_is_separate=0
    if mountpoint -q /boot 2>/dev/null; then
        _boot_is_separate=1
        echo "[DC] /boot è mountpoint reale"
    elif [ -n "$_boot_uuid" ] && [ "$_boot_uuid" != "$_root_uuid" ]; then
        # fstab dice /boot separata ma non è montata — probabilmente stale
        echo "[DC] WARN: fstab ha /boot UUID=$_boot_uuid ma /boot non è mountpoint — ignoro"
    fi
    if [ "$_boot_is_separate" -eq 1 ] && [ -n "$_boot_uuid" ] && [ "$_boot_uuid" != "$_root_uuid" ]; then
        _grub_root_uuid="$_boot_uuid"
        _path_prefix=""   # paths relativi alla root della boot partition
    else
        _grub_root_uuid="$_root_uuid"
        _path_prefix="/boot"
    fi

    local _linux_path="${_path_prefix}${_vmlinuz#/boot}"
    local _initrd_line=""
    [ -n "$_initrd" ] && _initrd_line="    initrd  ${_path_prefix}${_initrd#/boot}"

    # Legge GRUB_CMDLINE_LINUX da /etc/default/grub (contiene rd.luks.uuid= se LUKS)
    local _extra_opts=""
    _extra_opts=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub 2>/dev/null | \
        sed -e 's/^GRUB_CMDLINE_LINUX=//' -e 's/^"//' -e 's/"$//' \
            -e "s/^'//" -e "s/'$//")
    [ -n "$_extra_opts" ] && echo "[DC]   extra opts: ${_extra_opts}"

    local _timeout="5"
    _timeout=$(grep '^GRUB_TIMEOUT=' /etc/default/grub 2>/dev/null | \
        sed 's/^GRUB_TIMEOUT=//' | tr -d '"' | tr -d "'" || true)
    [ -z "$_timeout" ] && _timeout="5"

    # Percorsi per font e background (relativi alla /boot partition dopo search --set=root)
    local _grub_subdir
    case "$grub_cfg" in
        */grub2/*) _grub_subdir="grub2" ;;
        *)         _grub_subdir="grub"  ;;
    esac
    local _font_path="${_path_prefix}/${_grub_subdir}/fonts/unicode.pf2"
    local _bg_path="${_path_prefix}/${_grub_subdir}/distroClone-bg.png"

    mkdir -p "$(dirname "$grub_cfg")"
    cat > "$grub_cfg" << GRUBCFG
set default=0
set timeout=${_timeout}

insmod part_gpt
insmod ext2
insmod btrfs
insmod fat
insmod all_video
insmod font
insmod png
insmod gfxterm
insmod gfxterm_background

# Partizione /boot (contiene vmlinuz e initramfs)
search --no-floppy --set=root --fs-uuid ${_grub_root_uuid}

# Modalità grafica dark black (fallback a text se font o background mancante)
if loadfont ${_font_path} ; then
    set gfxmode=1024x768,auto
    terminal_output gfxterm
    if background_image ${_bg_path} ; then
        set color_normal=light-gray/black
        set color_highlight=white/dark-gray
    else
        set color_normal=light-gray/black
        set color_highlight=white/dark-gray
    fi
fi

menuentry '${_title}' --class linux --class os {
    insmod gzio
    insmod part_gpt
    insmod ext2
    insmod btrfs
    search --no-floppy --set=root --fs-uuid ${_grub_root_uuid}
    echo 'Loading ${_title} ...'
    linux   ${_linux_path} root=UUID=${_root_uuid} ro quiet loglevel=3${_extra_opts:+ ${_extra_opts}}
${_initrd_line}
}

if [ "\${grub_platform}" = "efi" ]; then
    menuentry 'UEFI Firmware Settings' \$menuentry_id_option 'uefi-firmware' {
        fwsetup
    }
fi
GRUBCFG

    echo "[DC] ✓ grub.cfg scritto: $grub_cfg"
    echo "[DC]   search root: UUID=${_grub_root_uuid}"
    echo "[DC]   linux:       ${_linux_path}"
    [ -n "$_initrd" ] && echo "[DC]   initrd:      ${_path_prefix}${_initrd#/boot}"
    echo "[DC]   boot_separate: ${_boot_is_separate}"

    # Verifica coerenza: il kernel deve essere accessibile come file reale
    if [ ! -f "$_vmlinuz" ]; then
        echo "[DC] WARN: $_vmlinuz non è un file reale (symlink rotto?)"
        # Tentativo: copia da /usr/lib/modules
        if [ -f "/usr/lib/modules/${_kver}/vmlinuz" ]; then
            cp "/usr/lib/modules/${_kver}/vmlinuz" "$_vmlinuz"
            echo "[DC] ✓ Kernel copiato da /usr/lib/modules/${_kver}/vmlinuz"
        fi
    fi
}

# =============================================================================
# Defrag + rewrite boot files su btrfs per fix GRUB "premature end of file"
# =============================================================================
# rsync Calamares crea file kernel/initramfs con layout extent sparse/multi-extent
# che GRUB btrfs driver legge male → "premature end of file /@/boot/vmlinuz-*".
# Osservato su Garuda 2026-04-20 (VM VirtualBox + hardware reale). Fix verificato:
# rewrite file con cp --sparse=never + btrfs filesystem defragment → 1 extent
# contiguo → GRUB legge corretto.
# Innocuo su altri distro btrfs (solo ottimizzazione layout).
dc_defrag_boot_files_btrfs() {
    # Skip se root non è btrfs
    local _root_fs
    _root_fs=$(awk '$2=="/" && $1!="none" {print $3}' /etc/fstab 2>/dev/null | head -1)
    [ "$_root_fs" != "btrfs" ] && return 0

    # Skip se btrfs tool non disponibile (raro, ma safe)
    command -v btrfs >/dev/null 2>&1 || { echo "[DC] btrfs tool mancante — skip defrag"; return 0; }

    echo "[DC] btrfs rilevato — rewrite + defrag /boot per fix extent GRUB"

    # Rewrite file sensibili (kernel, initramfs, microcode) senza sparse.
    # Identificazione: pattern comuni Arch/Garuda/Fedora/openSUSE/Debian.
    local _boot_dir="/boot"
    [ -d "$_boot_dir" ] || return 0

    local _tmpdir
    _tmpdir=$(mktemp -d /tmp/dc-boot-rewrite.XXXXXX 2>/dev/null) || { echo "[DC] WARN: mktemp fallito — skip defrag"; return 0; }

    local _rewrite_count=0
    local _f _base _tmp_target
    for _f in "${_boot_dir}"/vmlinuz-* \
              "${_boot_dir}"/vmlinux-* \
              "${_boot_dir}"/initramfs-*.img \
              "${_boot_dir}"/initrd.img-* \
              "${_boot_dir}"/initrd-*.img \
              "${_boot_dir}"/intel-ucode.img \
              "${_boot_dir}"/amd-ucode.img \
              "${_boot_dir}"/*-ucode.img; do
        [ -f "$_f" ] || continue
        _base=$(basename "$_f")
        _tmp_target="${_tmpdir}/${_base}"
        if cp --sparse=never --preserve=mode,ownership,timestamps "$_f" "$_tmp_target" 2>/dev/null; then
            if mv -f "$_tmp_target" "$_f" 2>/dev/null; then
                _rewrite_count=$((_rewrite_count + 1))
            fi
        fi
    done
    rm -rf "$_tmpdir" 2>/dev/null

    if [ "$_rewrite_count" -gt 0 ]; then
        echo "[DC] ✓ Rewrite senza sparse: ${_rewrite_count} file in ${_boot_dir}"
    fi

    # Defrag /boot ricorsivo: consolida extent chain su layout single-extent
    # che GRUB btrfs driver legge senza problemi.
    if btrfs filesystem defragment -r "${_boot_dir}" 2>/dev/null; then
        echo "[DC] ✓ btrfs defragment ${_boot_dir} completato"
    else
        echo "[DC] WARN: btrfs defragment ${_boot_dir} fallito (non-fatal)"
    fi

    sync 2>/dev/null || true
}

# =============================================================================
# grub-install + grub-mkconfig
# =============================================================================
dc_install_grub() {
    # Seleziona comando grub corretto (grub2 su Fedora/openSUSE, grub su altri)
    local grub_cmd grub_cfg_cmd grub_cfg
    if command -v grub2-install >/dev/null 2>&1; then
        grub_cmd="grub2-install"
        grub_cfg_cmd="grub2-mkconfig"
        grub_cfg="/boot/grub2/grub.cfg"
    else
        grub_cmd="grub-install"
        grub_cfg_cmd="grub-mkconfig"
        grub_cfg="/boot/grub/grub.cfg"
    fi

    # os-prober disabilitato: in VM scansiona CD-ROM virtuali → hang 10+ min
    sed -i '/^GRUB_DISABLE_OS_PROBER=/d' /etc/default/grub 2>/dev/null || true
    echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub

    # ── Estetica: dark black + nome distro centrato ─────────────────────────
    _dc_configure_grub_visual

    # Boot mode
    local boot_mode="bios"
    [ -d /sys/firmware/efi ] && boot_mode="uefi"

    # Bootloader ID dal distro (+ suffix "Clone" per evitare collisione NVRAM
    # e clobber EFI/<id>/ su ESP originale quando si installa il clone accanto
    # alla distro sorgente — DistroClone per definizione produce cloni).
    local distro_id bootloader_id
    distro_id=$(. /etc/os-release 2>/dev/null; echo "${ID:-linux}")
    bootloader_id=$(printf '%s' "$distro_id" | sed 's/./\u&/')Clone

    echo "[DC] grub-install: mode=$boot_mode cmd=$grub_cmd bootloader-id=$bootloader_id"

    if [ "$boot_mode" = "uefi" ]; then
        _dc_grub_uefi "$grub_cmd" "$bootloader_id"
    else
        _dc_grub_bios "$grub_cmd"
    fi

    # ── Fedora/openSUSE: BLS entries corrette prima di grub2-mkconfig ───────────
    # IMPORTANTE: le BLS entries estratte dallo squashfs del live possono avere:
    #   - paths con machine-id del live  (/<live_id>/<kver>/linux)
    #   - root=UUID=<uuid_live>          (UUID del dispositivo live, non del target)
    # grub2-mkconfig in modalità blscfg fa leggere le BLS a GRUB al boot:
    # se quelle entries puntano a file inesistenti → "file not found".
    # Soluzione: eliminare SEMPRE le BLS esistenti e ricreare da zero con paths verificati.
    if command -v grub2-install >/dev/null 2>&1; then
        local _bls_dir="/boot/loader/entries"
        mkdir -p "$_bls_dir"

        # Fix cross-partition symlink: openSUSE/Fedora mettono il kernel come symlink
        # da /boot → ../usr/lib/modules/<kver>/vmlinuz. Con /boot separata, GRUB non
        # può seguire symlink cross-partition → "file not found".
        # Soluzione: risolvi DENTRO il chroot dove stat() vede entrambe le partizioni.
        if mountpoint -q /boot 2>/dev/null; then
            echo "[DC] /boot separata — risolvo symlink kernel cross-partition..."
            for _ksym in /boot/vmlinuz-* /boot/vmlinuz /boot/Image-*; do
                [ -L "$_ksym" ] || continue
                _ksym_real=$(readlink -f "$_ksym" 2>/dev/null)
                if [ -f "$_ksym_real" ]; then
                    rm -f "$_ksym"
                    cp "$_ksym_real" "$_ksym"
                    echo "[DC] ✓ Symlink kernel risolto: $(basename "$_ksym")"
                else
                    echo "[DC] WARN: symlink $(basename "$_ksym") non risolvibile"
                fi
            done
            # Garantisce file reale anche se symlink mancava del tutto
            _kver_main=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)
            if [ -n "$_kver_main" ] && \
               ( [ ! -f "/boot/vmlinuz-${_kver_main}" ] || [ -L "/boot/vmlinuz-${_kver_main}" ] ) && \
               [ -f "/usr/lib/modules/${_kver_main}/vmlinuz" ]; then
                cp "/usr/lib/modules/${_kver_main}/vmlinuz" "/boot/vmlinuz-${_kver_main}"
                echo "[DC] ✓ Kernel copiato da /usr/lib/modules (fallback chroot)"
            fi
        fi

        # Elimina SEMPRE le BLS entries preesistenti (dal squashfs live o da runs precedenti).
        # Non usare kernel-install: può generare layout machine-id/kver/vmlinuz
        # invece di /vmlinuz-${kver} — comportamento variabile per versione.
        echo "[DC] Pulizia BLS entries preesistenti (potrebbero avere paths live errati)..."
        rm -f "${_bls_dir}"/*.conf 2>/dev/null || true

        local _kver
        _kver=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)

        if [ -n "$_kver" ]; then
            # Verifica il file vmlinuz reale nel target (può avere naming diverso)
            local _vmlinuz_path=""
            for _vf in "/boot/vmlinuz-${_kver}" "/boot/vmlinuz"; do
                [ -f "$_vf" ] && { _vmlinuz_path="$_vf"; break; }
            done

            # Verifica il file initramfs nel target (dracut crea initramfs-${kver}.img)
            local _initrd_path=""
            for _if in "/boot/initramfs-${_kver}.img" \
                       "/boot/initrd-${_kver}"        \
                       "/boot/initrd"; do
                [ -f "$_if" ] && { _initrd_path="$_if"; break; }
            done

            echo "[DC] vmlinuz: ${_vmlinuz_path:-MANCANTE}"
            echo "[DC] initrd:  ${_initrd_path:-MANCANTE}"

            if [ -n "$_vmlinuz_path" ]; then
                local _root_uuid
                _root_uuid=$(awk '$2=="/" {print $1}' /etc/fstab 2>/dev/null | \
                    sed 's|UUID=||')
                local _title
                _title=$(. /etc/os-release 2>/dev/null; \
                    echo "${PRETTY_NAME:-Linux} (${_kver})")

                # I paths BLS dipendono da se /boot è partizione separata:
                #   /boot separata: $root = boot partition → paths senza /boot/
                #   /boot su root:  $root = root partition → paths con /boot/
                # Usa mountpoint(1) per rilevare: funziona nel chroot Calamares perché
                # stat() paragona device IDs (indipendente da /proc/mounts host).
                local _bls_boot_sep=0
                mountpoint -q /boot 2>/dev/null && _bls_boot_sep=1
                local _bls_vmlinuz _bls_initrd=""
                if [ "$_bls_boot_sep" -eq 1 ]; then
                    _bls_vmlinuz="${_vmlinuz_path#/boot}"
                    [ -n "$_initrd_path" ] && _bls_initrd="${_initrd_path#/boot}"
                else
                    _bls_vmlinuz="${_vmlinuz_path}"
                    [ -n "$_initrd_path" ] && _bls_initrd="${_initrd_path}"
                fi

                # Legge GRUB_CMDLINE_LINUX (contiene rootflags=subvol=@ se btrfs, rd.luks.uuid= se LUKS)
                local _bls_extra=""
                _bls_extra=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub 2>/dev/null | \
                    sed -e 's/^GRUB_CMDLINE_LINUX=//' -e 's/^"//' -e 's/"$//' \
                        -e "s/^'//" -e "s/'$//")

                {
                    echo "title ${_title}"
                    echo "version ${_kver}"
                    echo "linux ${_bls_vmlinuz}"
                    [ -n "$_bls_initrd" ] && echo "initrd ${_bls_initrd}"
                    echo "options root=UUID=${_root_uuid} ro loglevel=3 quiet${_bls_extra:+ ${_bls_extra}}"
                    echo "id ${distro_id}-${_kver}"
                    echo "grub_users \$grub_users"
                    echo "grub_arg --unrestricted"
                    echo "grub_class kernel"
                } > "${_bls_dir}/${distro_id}-${_kver}.conf"

                echo "[DC] ✓ BLS entry: ${distro_id}-${_kver}.conf"
                echo "[DC]   linux:   ${_bls_vmlinuz}"
                [ -n "$_bls_initrd" ] && echo "[DC]   initrd:  ${_bls_initrd}"
                echo "[DC]   options: root=UUID=${_root_uuid}${_bls_extra:+ ${_bls_extra}}"
            else
                echo "[DC] WARN: vmlinuz non trovato in /boot — BLS entry non creata"
            fi
        else
            echo "[DC] WARN: nessun kernel in /lib/modules — BLS entries non create"
        fi
        echo "[DC] BLS entries: $(ls "${_bls_dir}"/*.conf 2>/dev/null | wc -l)"
    fi

    # ── grub.cfg ────────────────────────────────────────────────────────────────
    # grub2 (openSUSE/Fedora) con /boot separata: scrivi grub.cfg direttamente.
    # grub2-mkconfig dentro il chroot Calamares usa grub2-probe per trovare il
    # device di /boot; poiché /proc/mounts mostra path HOST (/tmp/calamares-root/boot)
    # invece di /boot, grub2-probe non riesce a matcharlo → usa UUID root partition
    # → GRUB cerca linux /vmlinuz-xxx sulla root → "file not found".
    #
    # Per grub (Debian/Arch) NON c'è questo problema (no partizione /boot separata
    # nel layout DistroClone, grub-mkconfig funziona correttamente).
    local _boot_uuid_check
    _boot_uuid_check=$(awk '$2=="/boot" {print $1}' /etc/fstab 2>/dev/null | sed 's|UUID=||')

    local _wrote_direct=0
    if command -v grub2-install >/dev/null 2>&1; then
        # grub2 (openSUSE/Fedora): SEMPRE scrittura diretta grub.cfg.
        # grub2-mkconfig in chroot Calamares fallisce sia con /boot separata
        # (grub2-probe vede path HOST /tmp/calamares-root/boot) sia senza
        # (grub2-probe non riesce a risolvere il device → path kernel errati).
        echo "[DC] grub2 → scrittura diretta $grub_cfg (bypass grub2-mkconfig)"
        if _dc_write_grub_cfg_direct "$grub_cfg"; then
            _wrote_direct=1
        else
            echo "[DC] WARN: scrittura diretta fallita — fallback su $grub_cfg_cmd"
        fi
    fi

    # ── Snapper cleanup before grub-mkconfig ────────────────────────────────
    # /.snapshots contains HOST btrfs snapshots inherited via rsync — always
    # purge them (they'd appear as phantom entries in the clone's GRUB menu).
    # Snapper config + openSUSE snapper-grub-plugin scripts are treated
    # differently per family:
    #   - openSUSE: destroy config (rebuilt at firstboot via dc-firstboot)
    #   - Arch (CachyOS): preserve config — grub-btrfs reads @snapshots
    #     natively and dc-firstboot runs `snapper create-config` only if missing.
    if [ "${DC_FAMILY:-${DC_DISTRO:-}}" = "opensuse" ]; then
        for _sg in /etc/grub.d/80_suse_btrfs_snapshot \
                   /etc/grub.d/81_suse_btrfs_snapshot; do
            if [ -x "$_sg" ]; then
                chmod -x "$_sg"
                echo "[DC] ✓ Disabilitato $_sg (snapper-grub-plugin)"
            fi
        done
    fi

    # Always: purge host /.snapshots contents (host-inherited subvolumes)
    if [ -d "/.snapshots" ]; then
        if command -v btrfs >/dev/null 2>&1; then
            for _snap in /.snapshots/*/snapshot; do
                [ -d "$_snap" ] && btrfs subvolume delete "$_snap" 2>/dev/null || true
            done
        fi
        rm -rf /.snapshots/* 2>/dev/null || true
        echo "[DC] ✓ /.snapshots pulito (rimossi snapshot host)"
    fi

    # Always: purge host snapper metadata
    rm -rf /var/lib/snapper/snapshots/* 2>/dev/null || true

    # openSUSE-only: remove snapper config + clear SNAPPER_CONFIGS sysconfig
    if [ "${DC_FAMILY:-${DC_DISTRO:-}}" = "opensuse" ]; then
        rm -f /etc/snapper/configs/root 2>/dev/null || true
        if [ -f /etc/sysconfig/snapper ]; then
            sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS=""/' /etc/sysconfig/snapper 2>/dev/null || true
            echo "[DC] ✓ SNAPPER_CONFIGS svuotato in /etc/sysconfig/snapper"
        fi
    else
        echo "[DC] ✓ snapper config preservata (DC_FAMILY=${DC_FAMILY:-${DC_DISTRO:-unknown}})"
    fi

    if [ "$_wrote_direct" -eq 0 ]; then
        # grub (Debian/Arch), grub2 senza /boot separata, o fallback dopo errore diretto
        echo "[DC] Generazione $grub_cfg con $grub_cfg_cmd ..."
        if "$grub_cfg_cmd" -o "$grub_cfg" 2>&1; then
            echo "[DC] ✓ $grub_cfg generato"
            if ! grep -q 'menuentry\|blscfg\|linux\b' "$grub_cfg" 2>/dev/null; then
                echo "[DC] WARN: $grub_cfg non contiene kernel entries"
            fi

            # ── FIX btrfs @ subvolume: rimuovi prefisso /@/ da path linux/initrd ──
            # CONDIZIONE CRITICA: strip /@/ solo se default subvol È @ effettivamente.
            #   - Default = @ + path /@/boot = "cerca @ dentro @" → fallisce
            #     Strip serve → path /boot relativo a @ → OK
            #   - Default = ID 5 (top-level) + path /@/boot = trova kernel a top-level → OK
            #     Strip BUCA il boot (path /boot non esiste a top-level, kernel sta in @/boot)
            # Verifica EFFETTIVA del default via `btrfs subvolume get-default` —
            # set-default può fallire silenziosamente (chroot, ro fs, tool mancante).
            local _dc_default_id _dc_at_id _dc_before_at _dc_after_at _dc_before_dup
            _dc_default_id=$(btrfs subvolume get-default / 2>/dev/null | awk '{print $2}' || true)
            _dc_at_id=$(btrfs subvolume list / 2>/dev/null | awk '/path @$/{print $2}' | head -1 || true)
            echo "[DC] btrfs default subvol ID=${_dc_default_id:-?} | @ subvol ID=${_dc_at_id:-?}"

            _dc_before_at=$(grep -cE '^[[:space:]]*(linux|linux16|linuxefi|initrd|initrd16|initrdefi)[[:space:]].*/@/' "$grub_cfg" 2>/dev/null || true)
            echo "[DC] grub.cfg pre-strip: ${_dc_before_at:-0} linee con /@/ su linux/initrd"

            if [ -n "$_dc_default_id" ] && [ -n "$_dc_at_id" ] && \
               [ "$_dc_default_id" = "$_dc_at_id" ] && \
               [ "${_dc_before_at:-0}" -gt 0 ]; then
                # Strip /@/ da TUTTI i path sulla linea. initrd può avere
                # microcode + initramfs: "initrd\t/@/boot/intel-ucode.img\t/@/boot/initramfs-*.img"
                # NOTA: grub.cfg usa TAB fra token — s-pattern deve usare [[:space:]]+
                # non spazio letterale, altrimenti match fallisce silenziosamente.
                sed -i -E '/^[[:space:]]*(linux|linux16|linuxefi|initrd|initrd16|initrdefi)[[:space:]]/ s#([[:space:]])/@/#\1/#g' "$grub_cfg" 2>&1
                _dc_after_at=$(grep -cE '^[[:space:]]*(linux|linux16|linuxefi|initrd|initrd16|initrdefi)[[:space:]].*/@/' "$grub_cfg" 2>/dev/null || true)
                if [ "${_dc_after_at:-0}" -eq 0 ]; then
                    echo "[DC] ✓ $grub_cfg: /@/ rimosso (${_dc_before_at} → 0, default=@)"
                else
                    echo "[DC] WARN: $grub_cfg: /@/ residui ${_dc_before_at} → ${_dc_after_at}"
                fi
            elif [ "${_dc_before_at:-0}" -gt 0 ]; then
                echo "[DC] /@/ presente MA default subvol ≠ @ (default=${_dc_default_id:-?} @=${_dc_at_id:-?})"
                echo "[DC] → NON strippo (path /@/boot funziona con default=top-level)"
            else
                # Caso inverso: default ≠ @ E grub.cfg ha path /boot SENZA /@/
                # → GRUB cerca kernel a top-level ma kernel sta in @/boot → boot fail
                # Fix: inject /@/ prima di /boot/ su linee linux/initrd
                # Osservato su Garuda: grub-mkconfig con fstab subvol=/@ genera path
                # senza /@/ prefix anche se default=5 (top-level). Serve prefix esplicito.
                local _dc_no_at_lines
                _dc_no_at_lines=$(grep -cE '^[[:space:]]*(linux|linux16|linuxefi|initrd|initrd16|initrdefi)[[:space:]].*[[:space:]]/boot/' "$grub_cfg" 2>/dev/null || true)
                if [ -n "$_dc_default_id" ] && [ -n "$_dc_at_id" ] && \
                   [ "$_dc_default_id" != "$_dc_at_id" ] && \
                   [ "${_dc_no_at_lines:-0}" -gt 0 ]; then
                    echo "[DC] default=top-level + ${_dc_no_at_lines} linee con /boot/ senza /@/ → inject /@/"
                    sed -i -E '/^[[:space:]]*(linux|linux16|linuxefi|initrd|initrd16|initrdefi)[[:space:]]/ s#([[:space:]])/boot/#\1/@/boot/#g' "$grub_cfg" 2>&1
                    echo "[DC] ✓ $grub_cfg: /@/ iniettato (default=top-level, kernel in @/boot)"
                fi
            fi

            # ── Dedupe rootflags=subvol=@ su linee linux ───────────────────
            _dc_before_dup=$(grep -cE '^[[:space:]]*linux[[:space:]].*rootflags=subvol=@.*rootflags=subvol=@' "$grub_cfg" 2>/dev/null || true)
            if [ "${_dc_before_dup:-0}" -gt 0 ]; then
                sed -i -E '/^[[:space:]]*linux[[:space:]]/{:a;s/(rootflags=subvol=\S+)[[:space:]]+rootflags=subvol=\S+/\1/g;ta}' "$grub_cfg" 2>/dev/null
                echo "[DC] ✓ $grub_cfg: rootflags=subvol=@ duplicati rimossi (${_dc_before_dup} linee)"
            fi

            # ── DIAGNOSTICA: stampa prime 2 entries linux + initrd ─────────
            echo "[DC] grub.cfg linux/initrd entries (primi):"
            grep -nE '^[[:space:]]*(linux|initrd)[[:space:]]' "$grub_cfg" 2>/dev/null | head -4 | sed 's/^/  /'
        else
            echo "[DC] ERROR: $grub_cfg_cmd fallito"
            return 1
        fi
    fi
}

# =============================================================================
# UEFI
# =============================================================================
_dc_grub_uefi() {
    local grub_cmd="$1" bootloader_id="$2"
    echo "[DC] UEFI: $grub_cmd --bootloader-id=$bootloader_id"

    # Nota: mountpoint -q /boot/efi fallisce dentro il chroot Calamares perché
    # /proc/mounts mostra il path HOST (/tmp/calamares-root/boot/efi), non /boot/efi.
    # grep su /proc/mounts cattura entrambe le forme ed è affidabile.
    if ! grep -q '/boot/efi' /proc/mounts 2>/dev/null; then
        echo "[DC] /boot/efi non in /proc/mounts — tentativo mount automatico"
        # Debug: aiuta a capire la situazione sul disco
        echo "[DC] DEBUG DISK=${DISK:-non definito}"
        echo "[DC] DEBUG fstab EFI: $(grep '/boot/efi' /etc/fstab 2>/dev/null | head -1 || echo 'assente')"
        [ -n "${DISK:-}" ] && \
            echo "[DC] DEBUG lsblk /dev/${DISK}: $(lsblk -lno NAME,PARTTYPE,FSTYPE "/dev/${DISK}" 2>/dev/null | tr '\n' '|')"

        # Tentativo 1: mount da fstab (scritto dal modulo fstab di Calamares)
        if grep -q '[[:space:]]/boot/efi[[:space:]]' /etc/fstab 2>/dev/null; then
            mkdir -p /boot/efi
            mount /boot/efi 2>/dev/null \
                && echo "[DC] ✓ /boot/efi montato da fstab" \
                || echo "[DC] WARN: mount da fstab fallito"
        else
            echo "[DC] DEBUG: /boot/efi assente da fstab — salto tentativo 1"
        fi

        # Tentativo 2: lsblk su DISK (già noto da dc-crypto.sh) — più affidabile
        # di blkid+UUID dentro il chroot dove /proc non è completamente inizializzato
        if ! grep -q '/boot/efi' /proc/mounts 2>/dev/null && [ -n "${DISK:-}" ]; then
            local _esp_dev=""
            # ESP per PARTTYPE (GUID EFI System Partition)
            _esp_dev=$(lsblk -lno NAME,PARTTYPE "/dev/${DISK}" 2>/dev/null \
                       | awk '/c12a7328-f81f-11d2-ba4b-00a0c93ec93b/ {print "/dev/"$1}' \
                       | head -1)
            # Fallback: prima partizione vfat sul disco target
            [ -z "$_esp_dev" ] && \
                _esp_dev=$(lsblk -lno NAME,FSTYPE "/dev/${DISK}" 2>/dev/null \
                           | awk '$2=="vfat" {print "/dev/"$1}' | head -1)
            if [ -n "$_esp_dev" ]; then
                mkdir -p /boot/efi
                mount "$_esp_dev" /boot/efi 2>/dev/null \
                    && echo "[DC] ✓ /boot/efi montato da $_esp_dev (lsblk/${DISK})" \
                    || echo "[DC] WARN: mount $_esp_dev fallito"
            else
                echo "[DC] WARN: nessuna partizione EFI/vfat su /dev/${DISK}"
            fi
        fi

        # Tentativo 3 RIMOSSO: blkid globale pescava prima ESP (head -1) fra tutti
        # i dischi collegati. In dual-disk (es. originale su sda + clone su sdb)
        # poteva mountare ESP sbagliato → clone sovrascriveva grubx64.efi originale.
        # Se DISK non definito o tentativi 1/2 falliscono, si preferisce skippare
        # grub-install UEFI piuttosto che rischiare clobber cross-disco.

        if ! grep -q '/boot/efi' /proc/mounts 2>/dev/null; then
            # Nessuna EFI trovata — uso intenzionale (es. multi-boot con rEFInd o
            # bootloader di altra distro). Skippiamo grub-install ma proseguiamo:
            # grub-mkconfig girerà comunque e genererà /boot/grub/grub.cfg.
            echo "[DC] WARN: /boot/efi non montato — grub-install UEFI saltato"
            echo "[DC] INFO: usa rEFInd o il bootloader della distro principale per avviare"
            return 0
        fi
    fi

    # timeout 60: ogni tentativo grub-install non può superare 60s
    timeout 60 "$grub_cmd" \
        --target=x86_64-efi --efi-directory=/boot/efi \
        --bootloader-id="$bootloader_id" --recheck --no-nvram 2>/dev/null \
    || timeout 60 "$grub_cmd" \
        --target=x86_64-efi --efi-directory=/boot/efi \
        --bootloader-id="$bootloader_id" --recheck 2>/dev/null \
    || timeout 60 "$grub_cmd" \
        --target=x86_64-efi --efi-directory=/boot/efi \
        --bootloader-id="$bootloader_id" --recheck --force --no-nvram
    echo "[DC] ✓ grub-install UEFI"

    # ── Check ESP appartiene al DISK target prima di scrivere fallback ──
    # Fallback EFI/BOOT/BOOTX64.EFI + --removable sono path "generici" letti
    # dal firmware UEFI quando utente sceglie "UEFI disk N" dal menu boot.
    # Se /boot/efi è stato mountato per errore su ESP di ALTRA distro (es.
    # Garuda originale), scrivere qui sovrascrive il bootloader originale.
    # Skip questi passi se sorgente mount /boot/efi non è su DISK target.
    local _esp_safe=1
    if [ -n "${DISK:-}" ]; then
        local _esp_src _esp_parent
        _esp_src=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null)
        _esp_parent=$(lsblk -no pkname "$_esp_src" 2>/dev/null | head -1)
        if [ -n "$_esp_parent" ] && [ "$_esp_parent" != "$DISK" ]; then
            _esp_safe=0
            echo "[DC] WARN: ESP ($_esp_src) su disco $_esp_parent ≠ DISK target ($DISK)"
            echo "[DC] INFO: skip fallback BOOTX64.EFI + --removable per evitare clobber cross-disco"
        fi
    fi

    if [ "$_esp_safe" -eq 1 ]; then
        # Fallback EFI (BOOTX64.EFI) — compatibilità VM/firmware permissivi
        local efi_src="/boot/efi/EFI/${bootloader_id}/grubx64.efi"
        if [ -f "$efi_src" ]; then
            mkdir -p /boot/efi/EFI/BOOT
            cp -f "$efi_src" /boot/efi/EFI/BOOT/BOOTX64.EFI && \
                echo "[DC] ✓ Fallback EFI: BOOTX64.EFI" || \
                echo "[DC] WARN: fallback EFI fallito (non critico)"
        fi

        # Removable (non critico — alcune VM non supportano --removable)
        timeout 60 "$grub_cmd" \
            --target=x86_64-efi --efi-directory=/boot/efi --removable --recheck \
            2>/dev/null || echo "[DC] WARN: grub removable fallito (non critico)"
    fi
}

# =============================================================================
# Estetica GRUB: dark black + nome distro centrato
# =============================================================================
_dc_configure_grub_visual() {
    local _distro_pretty
    _distro_pretty=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")

    # GRUB_DISTRIBUTOR: nome distro visibile nelle voci del menu
    sed -i '/^GRUB_DISTRIBUTOR=/d' /etc/default/grub 2>/dev/null || true
    echo "GRUB_DISTRIBUTOR=\"${_distro_pretty}\"" >> /etc/default/grub

    # Modalità grafica + colori dark black
    sed -i '/^GRUB_GFXMODE=/d; /^GRUB_GFXPAYLOAD_LINUX=/d' \
        /etc/default/grub 2>/dev/null || true
    echo 'GRUB_GFXMODE="1024x768,auto"' >> /etc/default/grub
    echo 'GRUB_GFXPAYLOAD_LINUX="keep"' >> /etc/default/grub
    sed -i '/^GRUB_COLOR_NORMAL=/d; /^GRUB_COLOR_HIGHLIGHT=/d' \
        /etc/default/grub 2>/dev/null || true
    echo 'GRUB_COLOR_NORMAL="light-gray/black"' >> /etc/default/grub
    echo 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' >> /etc/default/grub

    # Background nero con nome distro centrato (uguale alla live ISO)
    local _grub_dir="/boot/grub"
    [ -d /boot/grub2 ] && _grub_dir="/boot/grub2"
    local _bg="${_grub_dir}/distroClone-bg.png"

    local _IM_CMD=""
    command -v magick  >/dev/null 2>&1 && _IM_CMD="magick"
    command -v convert >/dev/null 2>&1 && _IM_CMD="${_IM_CMD:-convert}"

    if [ -n "$_IM_CMD" ]; then
        local _font=""
        for _fp in \
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
            "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf" \
            "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf" \
            "/usr/share/fonts/dejavu-sans/DejaVuSans-Bold.ttf"; do
            [ -f "$_fp" ] && _font="$_fp" && break
        done

        if [ -n "$_font" ]; then
            $_IM_CMD -size 1024x768 -depth 8 \
                gradient:'#111111'-'#000000' \
                -gravity center \
                -font "$_font" -pointsize 36 \
                -fill white -annotate +0-40 "${_distro_pretty}" \
                -font "$_font" -pointsize 18 \
                -fill '#888888' -annotate +0+20 "Boot Menu" \
                -depth 8 -type TrueColor \
                -define png:color-type=2 -define png:bit-depth=8 \
                "$_bg" 2>/dev/null \
            && echo "[DC] ✓ GRUB background: nome distro centrato su gradiente nero" \
            || $_IM_CMD -size 1024x768 gradient:'#111111'-'#000000' \
                -depth 8 -type TrueColor \
                -define png:color-type=2 -define png:bit-depth=8 \
                "$_bg" 2>/dev/null \
            && echo "[DC] ✓ GRUB background: gradiente nero (font non trovato)"
        else
            $_IM_CMD -size 1024x768 gradient:'#111111'-'#050505' \
                -depth 8 -type TrueColor \
                -define png:color-type=2 -define png:bit-depth=8 \
                "$_bg" 2>/dev/null \
            && echo "[DC] ✓ GRUB background: gradiente nero (no font)"
        fi

        if [ -f "$_bg" ]; then
            sed -i '/^GRUB_BACKGROUND=/d' /etc/default/grub 2>/dev/null || true
            echo "GRUB_BACKGROUND=\"${_bg}\"" >> /etc/default/grub
            echo "[DC] ✓ GRUB_BACKGROUND=${_bg}"
        fi
    else
        echo "[DC] ImageMagick non trovato — GRUB background non generato (non critico)"
    fi

    echo "[DC] ✓ GRUB estetica dark black configurata (distro: ${_distro_pretty})"
}

# =============================================================================
# BIOS
# =============================================================================
_dc_grub_bios() {
    local grub_cmd="$1"
    echo "[DC] BIOS: $grub_cmd"

    # findmnt / non funziona nel chroot → identifica disco da fstab + cryptsetup
    # _dc_get_root_dev() e _dc_get_disk() sono definiti in dc-crypto.sh (già sourciato)
    local root_dev
    root_dev=$(_dc_get_root_dev)

    local disk
    disk=$(_dc_get_disk "$root_dev")
    [ -z "$disk" ] && disk="${DISK_DEV:-sda}"

    echo "[DC] BIOS: disco=$disk (root_dev=$root_dev)"

    # timeout 60: se grub-install si blocca (es. EFI context sbagliato), fallisce pulito
    if timeout 60 "$grub_cmd" --target=i386-pc --recheck "/dev/$disk" 2>&1; then
        echo "[DC] ✓ grub-install BIOS su /dev/$disk"
    else
        echo "[DC] ERROR: $grub_cmd BIOS fallito su /dev/$disk"
        return 1
    fi
}
DCGRUB

chmod 755 /usr/local/lib/distroClone/dc-crypto.sh           /usr/local/lib/distroClone/dc-initramfs.sh           /usr/local/lib/distroClone/dc-grub.sh
echo "[DC] ✓ Moduli installati in /usr/local/lib/distroClone/"

# ── calamares-grub-install.sh (wrapper, dontChroot: true → live system) ───────
# Eseguito sul sistema LIVE (non chrooted) da Calamares.
# Rimonta /proc /sys /dev /run nel target (rebuild-initramfs li ha smontati),
# poi esegue calamares-grub-inner.sh dentro il chroot target.
# Senza /sys/firmware/efi il rilevamento UEFI fallisce silenziosamente
# (grub2-install tenta BIOS su /dev/sda senza /dev → exit 1 dopo BOOT_DEV).
install -Dm755 /dev/stdin /usr/local/bin/calamares-grub-install.sh << 'GRUBWRAPPER'
#!/bin/bash
set -e
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"

echo "════════════════════════════════════════════════════════"
echo "  DistroClone calamares-grub-install  (unified layer)"
echo "════════════════════════════════════════════════════════"

# Diagnostica: stampa mount points con /etc (safe con set -e: usa || true ovunque)
echo "[DC] Mount points con /etc:"
while IFS= read -r _dbg_mp; do
    if [ -d "$_dbg_mp/etc" ]; then echo "  $_dbg_mp"; fi
done < <(findmnt -n -l -o TARGET 2>/dev/null) || true
if [ -d /tmp/calamares-root ]; then
    echo "[DC] /tmp/calamares-root esiste — contenuto root: $(ls /tmp/calamares-root/ 2>/dev/null | tr '\n' ' ' || true)"
else
    echo "[DC] /tmp/calamares-root NON esiste"
fi

TARGET=""
# 1. /tmp/calamares-root solo se è un VERO mount point
#    (non una directory plain creata da operazioni precedenti)
if mountpoint -q /tmp/calamares-root 2>/dev/null && [ -d /tmp/calamares-root/etc ]; then
    TARGET="/tmp/calamares-root"
fi
# 2. /tmp/calamares-root-* (Calamares 3.3+ usa suffisso univoco per run)
if [ -z "$TARGET" ]; then
    while IFS= read -r _mp; do
        case "$_mp" in /tmp/calamares-root-*)
            if [ -d "$_mp/etc" ]; then TARGET="$_mp"; break; fi ;;
        esac
    done < <(findmnt -n -l -o TARGET 2>/dev/null) || true
fi
# 3. Fallback: mount point standard con etc/ e usr/ (esclude fs virtuali)
if [ -z "$TARGET" ]; then
    for _mp in /mnt/target /target /mnt; do
        if mountpoint -q "$_mp" 2>/dev/null && [ -d "$_mp/etc" ]; then
            TARGET="$_mp"; break
        fi
    done
fi
# 4. Ultima risorsa: scansione findmnt, esclude root e fs virtuali
if [ -z "$TARGET" ]; then
    while IFS= read -r _mp; do
        case "$_mp" in
            /|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/tmp) continue ;;
        esac
        if mountpoint -q "$_mp" 2>/dev/null && [ -d "$_mp/etc" ] && [ -d "$_mp/usr" ]; then
            TARGET="$_mp"; break
        fi
    done < <(findmnt -n -l -o TARGET 2>/dev/null) || true
fi
if [ -z "$TARGET" ]; then
    echo "[ERROR] Target non trovato in nessun mount point"
    echo "  Mount attivi:"
    findmnt -n -l -o TARGET,SOURCE,FSTYPE 2>/dev/null || mount | awk '{print $3}' || true
    exit 1
fi
echo "[DC] Target rilevato: $TARGET"
# Se calamares-grub-inner.sh manca nel target ma esiste sull'host, copialo
if [ ! -f "$TARGET/usr/local/bin/calamares-grub-inner.sh" ]; then
    if [ -f /usr/local/bin/calamares-grub-inner.sh ]; then
        echo "[DC] WARN: calamares-grub-inner.sh mancante in target — copio da host"
        mkdir -p "$TARGET/usr/local/bin"
        cp /usr/local/bin/calamares-grub-inner.sh "$TARGET/usr/local/bin/calamares-grub-inner.sh"
        chmod 755 "$TARGET/usr/local/bin/calamares-grub-inner.sh"
    else
        echo "[ERROR] calamares-grub-inner.sh non trovato né in target né su host"
        exit 1
    fi
fi

# ── VERIFICA CRITICA: fstab deve esistere e contenere root entry ─────────────
# Se il modulo fstab C++ E dc-write-fstab hanno entrambi fallito, il sistema
# non può avviare. Controlliamo PRIMA di procedere con grub.
if [ ! -f "$TARGET/etc/fstab" ] || ! grep -qE '^UUID=|^LABEL=|^/dev/' "$TARGET/etc/fstab" 2>/dev/null; then
    echo "[DC] ALERT: $TARGET/etc/fstab mancante o vuoto — tentativo riparazione"
    # Rileva UUID dalla partizione root montata
    _FSTAB_ROOT_DEV=$(findmnt -n -o SOURCE "$TARGET" 2>/dev/null | head -1)
    [ -z "$_FSTAB_ROOT_DEV" ] && \
        _FSTAB_ROOT_DEV=$(awk -v mp="$TARGET" '$2==mp {print $1}' /proc/mounts 2>/dev/null | tail -1)
    _FSTAB_ROOT_UUID=""
    _FSTAB_ROOT_FS=""
    if [ -n "$_FSTAB_ROOT_DEV" ]; then
        _FSTAB_ROOT_UUID=$(blkid -s UUID -o value "$_FSTAB_ROOT_DEV" 2>/dev/null)
        _FSTAB_ROOT_FS=$(blkid -s TYPE -o value "$_FSTAB_ROOT_DEV" 2>/dev/null)
    fi
    _FSTAB_ROOT_FS="${_FSTAB_ROOT_FS:-ext4}"

    _FSTAB_BOOT_LINE=""
    if mountpoint -q "$TARGET/boot" 2>/dev/null; then
        _FSTAB_BOOT_DEV=$(findmnt -n -o SOURCE "$TARGET/boot" 2>/dev/null | head -1)
        [ -z "$_FSTAB_BOOT_DEV" ] && \
            _FSTAB_BOOT_DEV=$(awk -v mp="$TARGET/boot" '$2==mp {print $1}' /proc/mounts 2>/dev/null | tail -1)
        if [ -n "$_FSTAB_BOOT_DEV" ]; then
            _FSTAB_BOOT_UUID=$(blkid -s UUID -o value "$_FSTAB_BOOT_DEV" 2>/dev/null)
            _FSTAB_BOOT_FS=$(blkid -s TYPE -o value "$_FSTAB_BOOT_DEV" 2>/dev/null)
            [ -n "$_FSTAB_BOOT_UUID" ] && \
                _FSTAB_BOOT_LINE="UUID=$_FSTAB_BOOT_UUID  /boot  ${_FSTAB_BOOT_FS:-ext4}  defaults,noatime  0  2"
        fi
    fi

    _FSTAB_EFI_LINE=""
    for _efi_mp in "$TARGET/boot/efi" "$TARGET/efi"; do
        if mountpoint -q "$_efi_mp" 2>/dev/null; then
            _FSTAB_EFI_DEV=$(findmnt -n -o SOURCE "$_efi_mp" 2>/dev/null | head -1)
            [ -z "$_FSTAB_EFI_DEV" ] && \
                _FSTAB_EFI_DEV=$(awk -v mp="$_efi_mp" '$2==mp {print $1}' /proc/mounts 2>/dev/null | tail -1)
            if [ -n "$_FSTAB_EFI_DEV" ]; then
                _FSTAB_EFI_UUID=$(blkid -s UUID -o value "$_FSTAB_EFI_DEV" 2>/dev/null)
                _efi_rel="${_efi_mp#$TARGET}"
                [ -n "$_FSTAB_EFI_UUID" ] && \
                    _FSTAB_EFI_LINE="UUID=$_FSTAB_EFI_UUID  $_efi_rel  vfat  umask=0077  0  2"
            fi
            break
        fi
    done

    if [ -n "$_FSTAB_ROOT_UUID" ]; then
        _FSTAB_ROOT_OPTS="defaults,noatime"
        if [ "$_FSTAB_ROOT_FS" = "btrfs" ]; then
            _FSTAB_ROOT_OPTS="defaults,noatime,compress=zstd"
            # Rileva subvolume @ (layout openSUSE TW): se presente, fstab deve usare subvol=@
            if btrfs subvolume list "$TARGET" 2>/dev/null | grep -qE '(^|\s)path @$'; then
                _FSTAB_ROOT_OPTS="defaults,noatime,compress=zstd,subvol=@"
                echo "[DC] btrfs emergency fstab: subvolume @ trovato — usa subvol=@"
            fi
        fi
        {
            echo "# /etc/fstab — emergency repair by DistroClone $(date)"
            echo "UUID=$_FSTAB_ROOT_UUID  /  $_FSTAB_ROOT_FS  $_FSTAB_ROOT_OPTS  0  1"
            # Includi subvolumi btrfs standard:
            #   openSUSE TW (nested): @/home, @/var, @/usr/local, @/srv, @/opt, @/root, @/.snapshots
            #   CachyOS/Arch (flat):  @home, @srv, @root, @var/cache, @var/log, @var/tmp, @snapshots
            if [ "$_FSTAB_ROOT_FS" = "btrfs" ]; then
                _ER_BTRFS_OPTS="defaults,noatime,compress=zstd"
                _ER_SV_LIST=$(btrfs subvolume list "$TARGET" 2>/dev/null | awk '{print $NF}' | sort)
                for _sv in $_ER_SV_LIST; do
                    case "$_sv" in
                        # nested (openSUSE TW)
                        @/home)       _sv_mp="/home" ;;
                        @/var)        _sv_mp="/var" ;;
                        @/usr/local)  _sv_mp="/usr/local" ;;
                        @/srv)        _sv_mp="/srv" ;;
                        @/opt)        _sv_mp="/opt" ;;
                        @/root)       _sv_mp="/root" ;;
                        @/.snapshots) _sv_mp="/.snapshots" ;;
                        # flat (CachyOS / Arch)
                        @home)        _sv_mp="/home" ;;
                        @srv)         _sv_mp="/srv" ;;
                        @root)        _sv_mp="/root" ;;
                        @var/cache)   _sv_mp="/var/cache" ;;
                        @var/log)     _sv_mp="/var/log" ;;
                        @var/tmp)     _sv_mp="/var/tmp" ;;
                        @snapshots)   _sv_mp="/.snapshots" ;;
                        # skip root subvol and anything else
                        @|*)          continue ;;
                    esac
                    echo "UUID=$_FSTAB_ROOT_UUID  $_sv_mp  btrfs  ${_ER_BTRFS_OPTS},subvol=${_sv}  0  0"
                done
            fi
            [ -n "$_FSTAB_BOOT_LINE" ] && echo "$_FSTAB_BOOT_LINE"
            [ -n "$_FSTAB_EFI_LINE" ]  && echo "$_FSTAB_EFI_LINE"
            echo "tmpfs  /tmp  tmpfs  defaults  0  0"
        } > "$TARGET/etc/fstab"
        echo "[DC] ✓ fstab riparato: root=UUID=$_FSTAB_ROOT_UUID (${_FSTAB_ROOT_FS})"
    else
        echo "[DC] WARN: impossibile determinare UUID root — fstab potrebbe essere invalido"
        echo "[DC] mount info: $(mount | grep calamares 2>/dev/null || echo 'N/A')"
    fi
fi
echo "[DC] Verifica fstab:"; cat "$TARGET/etc/fstab" 2>/dev/null | head -10 || echo "  MANCANTE!"

echo "[DC] Mounting virtual filesystems in $TARGET ..."
for _d in proc sys dev dev/pts run; do
    mkdir -p "$TARGET/$_d"
    case "$_d" in
        proc) mount -t proc  proc   "$TARGET/proc"    2>/dev/null \
                && echo "[DC] ✓ proc"    || echo "[DC] WARN: proc già montato" ;;
        sys)  mount -t sysfs sysfs  "$TARGET/sys"     2>/dev/null \
                && echo "[DC] ✓ sys"     || echo "[DC] WARN: sys già montato" ;;
        *)    mount --bind "/$_d" "$TARGET/$_d"       2>/dev/null \
                && echo "[DC] ✓ bind $_d" || echo "[DC] WARN: bind $_d fallito" ;;
    esac
done

_RC=0
chroot "$TARGET" /usr/local/bin/calamares-grub-inner.sh || _RC=$?

echo "[DC] Unmounting virtual filesystems ..."
for _d in dev/pts dev run sys proc; do
    umount -l "$TARGET/$_d" 2>/dev/null || true
done

if [ "$_RC" -eq 0 ]; then
    echo "[OK] calamares-grub-install completato"
else
    echo "[ERROR] calamares-grub-inner.sh exit $_RC"
fi
exit $_RC
GRUBWRAPPER

# ── calamares-grub-inner.sh (worker, eseguito dentro il chroot target) ────────
# BASH_SOURCE[0] = /usr/local/bin/calamares-grub-inner.sh (path reale nel chroot)
# → dc_crypto_apply trova dc-initramfs.sh e dc-grub.sh via dirname(BASH_SOURCE[0]).
# NON usare heredoc stdin: BASH_SOURCE[0] sarebbe /dev/stdin → path errato.
install -Dm755 /dev/stdin /usr/local/bin/calamares-grub-inner.sh << 'GRUBINNER'
#!/bin/bash
set -e
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"

DC_LIB="/usr/local/lib/distroClone"

if [ ! -f "${DC_LIB}/dc-crypto.sh" ]; then
    echo "[ERROR] ${DC_LIB}/dc-crypto.sh non trovato nel target"
    exit 1
fi

source "${DC_LIB}/dc-crypto.sh"
dc_crypto_apply

# ── SAFETY NET FINALE: strip /@/ da grub.cfg come ultima linea di difesa ──
# STRIP SOLO SE default subvol = @ effettivamente (non si fida di set-default:
# path /@/boot funziona con default=top-level, strip buca il boot!).
_sn_default_id=$(btrfs subvolume get-default / 2>/dev/null | awk '{print $2}' || true)
_sn_at_id=$(btrfs subvolume list / 2>/dev/null | awk '/path @$/{print $2}' | head -1 || true)
if [ -n "$_sn_default_id" ] && [ -n "$_sn_at_id" ] && \
   [ "$_sn_default_id" = "$_sn_at_id" ]; then
    echo "[DC safety-net] default subvol = @ (ID=$_sn_at_id) → strip /@/ sicuro"
    for _sf_cfg in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
        [ -f "$_sf_cfg" ] || continue
        if grep -qE '^[[:space:]]*(linux|initrd)[[:space:]].*/@/' "$_sf_cfg" 2>/dev/null; then
            sed -i -E '/^[[:space:]]*(linux|linux16|linuxefi|initrd|initrd16|initrdefi)[[:space:]]/ s#([[:space:]])/@/#\1/#g' "$_sf_cfg" 2>&1
            sed -i -E '/^[[:space:]]*linux[[:space:]]/{:a;s/(rootflags=subvol=\S+)[[:space:]]+rootflags=subvol=\S+/\1/g;ta}' "$_sf_cfg" 2>/dev/null || true
            echo "[DC safety-net] ✓ $_sf_cfg strip applicato"
        fi
    done
elif [ -n "$_sn_default_id" ] && [ -n "$_sn_at_id" ] && \
     [ "$_sn_default_id" != "$_sn_at_id" ]; then
    # default = top-level + kernel in @/boot → path senza /@/ non bootano
    # (grub-mkconfig Garuda con fstab subvol=/@ genera path bug)
    echo "[DC safety-net] default=top-level (ID=$_sn_default_id) ≠ @ (ID=$_sn_at_id) → check inject /@/"
    for _sf_cfg in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
        [ -f "$_sf_cfg" ] || continue
        if grep -qE '^[[:space:]]*(linux|initrd)[[:space:]].*[[:space:]]/boot/' "$_sf_cfg" 2>/dev/null \
           && ! grep -qE '^[[:space:]]*(linux|initrd)[[:space:]].*/@/boot/' "$_sf_cfg" 2>/dev/null; then
            sed -i -E '/^[[:space:]]*(linux|linux16|linuxefi|initrd|initrd16|initrdefi)[[:space:]]/ s#([[:space:]])/boot/#\1/@/boot/#g' "$_sf_cfg" 2>&1
            echo "[DC safety-net] ✓ $_sf_cfg inject /@/ applicato"
        fi
    done
else
    echo "[DC safety-net] default subvol ID=${_sn_default_id:-?} ≠ @ ID=${_sn_at_id:-?} — NO strip"
fi

echo "[OK] calamares-grub-inner completato"
GRUBINNER

write_shellprocess_conf /etc/calamares/modules/grubinstall.conf true 1200 \
    /usr/local/bin/calamares-grub-install.sh

# =============================================================================
# 8b. HOOK SPECIFICI FAMIGLIA (dracut rebuild, cleanup-live-conf, etc.)
# =============================================================================
dc_configure_family

# =============================================================================
# 8c. REMOVE-LIVE-USER
# =============================================================================
echo "[8b/9] remove-live-user.conf"
dc_remove_live_user

write_shellprocess_conf /etc/calamares/modules/remove-live-user.conf false 120 \
"-/usr/local/bin/dc-remove-live-user.sh"

# =============================================================================
# 8d. POST-USERS
# =============================================================================
echo "[8c/9] dc-post-users.conf"

cat > /usr/local/bin/dc-post-users.sh << 'POSTUSERSCRIPT'
#!/bin/bash
# dc-post-users.sh — crea /home/UTENTE dopo il modulo users di Calamares
# Usa stdout diretto (MAI exec >file): Calamares cattura stdout dal processo.
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"

# Leggi password fallback dall'ambiente live
[ -f /tmp/dc_env.sh ] && . /tmp/dc_env.sh
_DC_FALLBACK_PWD="${DC_ROOT_PASSWORD:-distroClone1!}"

mkdir -p /var/log 2>/dev/null || true
# Log diagnostico persistente (tee per singoli comandi, mai exec > file)
_DC_LOG=/var/log/dc-post-users.log
{ echo "=== DistroClone post-users $(date) ==="; echo "DC_FALLBACK_PWD=${_DC_FALLBACK_PWD}"; } | tee -a "$_DC_LOG"

_LIVE_USER="$(tr -d '[:space:]' < /etc/distroClone-live-user 2>/dev/null || true)"
echo "Live user marker: ${_LIVE_USER:-NOT FOUND}"

# ── Fix /etc/shadow permissions ────────────────────────────────────────────
if ! getent group shadow >/dev/null 2>&1; then
    groupadd -g 42 shadow 2>/dev/null || groupadd shadow 2>/dev/null || true
fi
chown root:shadow /etc/shadow 2>/dev/null || true
chmod 640 /etc/shadow 2>/dev/null || true
echo "OK: /etc/shadow -> 640 root:shadow"

# ── Crea /home/UTENTE per tutti gli utenti installati (UID 1000-65533) ────
# Questo loop è più robusto di find_real_user: non filtra per shell,
# quindi funziona su openSUSE/Fedora/Arch indipendentemente dal valore userShell.
# Il live user è già rimosso da remove-live-user; il filtro _LIVE_USER è
# un doppio controllo per sicurezza.
echo ""
echo "=== Home directories ==="
mkdir -p /home

_FOUND_USERS=0
while IFS=: read -r _u _x _uid _gid _gecos _home _shell; do
    [ "$_uid" -ge 1000 ] 2>/dev/null || continue
    [ "$_uid" -lt 65534 ] 2>/dev/null || continue
    [ "$_u" = "nobody" ] && continue
    # Filtra live user (già rimosso da remove-live-user — doppio controllo)
    [ -n "$_LIVE_USER" ] && [ "$_u" = "$_LIVE_USER" ] && continue
    # Solo home sotto /home/
    case "$_home" in /home/*) ;; *) continue ;; esac

    _FOUND_USERS=$(( _FOUND_USERS + 1 ))
    echo "Utente: $_u (uid=$_uid gid=$_gid home=$_home)"

    mkdir -p "$_home"
    if [ ! -e "$_home/.bashrc" ] && [ -d /etc/skel ]; then
        cp -a /etc/skel/. "$_home/" 2>/dev/null || true
        echo "  -> home inizializzata da /etc/skel"
    fi

    _gname="$(getent group "$_gid" 2>/dev/null | cut -d: -f1)"
    [ -z "$_gname" ] && _gname="users"
    chown -R "$_u:$_gname" "$_home" 2>/dev/null || true
    chmod 700 "$_home" 2>/dev/null || true
    echo "  -> OK: $_home (owner $_u:$_gname)"

    # Fix password hash.
    # Tre casi distinti per evitare regressioni:
    #   1. hash VUOTO/!/!!/*  → nessuna password valida → imposta fallback
    #   2. !$... / !!$...     → password Calamares valida ma locked → solo unlock
    #   3. $...               → già valida → no-op
    _hash="$(grep "^${_u}:" /etc/shadow 2>/dev/null | cut -d: -f2)"
    case "$_hash" in
        ""|"!"|"!!"|"*")
            echo "  WARN: hash vuoto/locked-senza-password (${_hash:-empty}) — imposto fallback"
            echo "${_u}:${_DC_FALLBACK_PWD}" | chpasswd 2>/dev/null || \
            echo "${_DC_FALLBACK_PWD}" | passwd --stdin "$_u" 2>/dev/null || true
            ;;
        "!"*)
            echo "  WARN: hash locked CON password Calamares (${_hash:0:4}...) — solo unlock"
            usermod -U "$_u" 2>/dev/null || passwd -u "$_u" 2>/dev/null || true
            ;;
        *)
            echo "  OK: password hash valido (${_hash:0:6}...)"
            ;;
    esac
done < /etc/passwd

if [ "$_FOUND_USERS" -eq 0 ]; then
    echo "WARN: nessun utente UID>=1000 trovato in /etc/passwd"
    echo "Contenuto /etc/passwd (ultimi 15):"
    tail -15 /etc/passwd
else
    echo ""
    echo "Home directory /home:"
    ls -la /home/ 2>/dev/null
fi

# ── Fix password root: stesso tri-case dell'utente ────────────────────────
_root_hash="$(grep '^root:' /etc/shadow 2>/dev/null | cut -d: -f2)"
case "$_root_hash" in
    ""|"!"|"!!"|"*")
        echo ""
        echo "WARN: root hash vuoto/locked-senza-password (${_root_hash:-empty}) — imposto fallback"
        echo "root:${_DC_FALLBACK_PWD}" | chpasswd 2>/dev/null || \
        echo "${_DC_FALLBACK_PWD}" | passwd --stdin root 2>/dev/null || true
        ;;
    "!"*)
        echo ""
        echo "WARN: root hash locked CON password (${_root_hash:0:4}...) — solo unlock"
        usermod -U root 2>/dev/null || passwd -u root 2>/dev/null || true
        ;;
    *)
        echo "OK: root password hash valido (${_root_hash:0:6}...)"
        ;;
esac

# ── DUMP DIAGNOSTICO FINALE su log persistente ────────────────────────────
# Redacted: mostra solo i primi 6 char dell'hash (sufficienti per distinguere
# $6$, $y$, !*, vuoto — senza esporre il hash completo).
{
    echo ""
    echo "=== /etc/shadow (redacted) $(date) ==="
    awk -F: '$2!="" {printf "  %-20s hash=%.8s... field3=%s\n",$1,$2,$3}' /etc/shadow 2>/dev/null
    echo ""
    echo "=== /etc/passwd (UID >= 0 e root) ==="
    awk -F: '$3==0 || $3>=1000 {printf "  %-20s uid=%s gid=%s home=%s shell=%s\n",$1,$3,$4,$6,$7}' /etc/passwd 2>/dev/null
    echo "=== fine dump ==="
} | tee -a "$_DC_LOG"

# ── Servizio firstboot: crea /home se mancante al primo avvio ─────────────
# Safety net: se la home non viene creata durante l'installazione (es. btrfs
# subvolume montato su /home nasconde il contenuto), il servizio la crea al
# primo boot quando tutti i filesystem sono correttamente montati.
mkdir -p /usr/local/bin
cat > /usr/local/bin/dc-firstboot.sh << 'FBEOF'
#!/bin/bash
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"

# ── SAFETY NET /tmp/.X11-unix (bug CachyOS gnome-shell Wayland) ───────────
# Se al boot /tmp/.X11-unix ha ownership errata, gnome-shell crasha su
# Wayland con "Failed to start X Wayland: Wrong ownership" → GDM torna al
# greeter dopo aver accettato la password ("Session never registered").
# Fix primario è /etc/tmpfiles.d/zz-dc-x11-unix.conf (gira prima di
# display-manager). Questa è safety net idempotente: se esiste ma con
# permessi sbagliati, li correggi. Girata nel firstboot è utile solo se
# il systemd-tmpfiles drop-in non ha funzionato per qualche motivo.
if [ -e /tmp/.X11-unix ]; then
    chown root:root /tmp/.X11-unix 2>/dev/null || true
    chmod 1777 /tmp/.X11-unix 2>/dev/null || true
fi
# Riapplica tmpfiles.d (rigenera anche X11-unix se rimossa)
systemd-tmpfiles --create 2>/dev/null || true

echo "[DC firstboot] Verifica home directories..."
while IFS=: read -r _u _x _uid _gid _gecos _home _shell; do
    [ "$_uid" -ge 1000 ] 2>/dev/null || continue
    [ "$_uid" -lt 65534 ] 2>/dev/null || continue
    [ "$_u" = "nobody" ] && continue
    case "$_home" in /home/*) ;; *) continue ;; esac
    [ -d "$_home" ] && continue
    echo "[DC firstboot] Creo $_home per $_u"
    mkdir -p "$_home"
    [ -d /etc/skel ] && cp -a /etc/skel/. "$_home/" 2>/dev/null || true
    _gname="$(getent group "$_gid" 2>/dev/null | cut -d: -f1)"
    [ -z "$_gname" ] && _gname="users"
    chown -R "$_u:$_gname" "$_home"
    chmod 700 "$_home"
    echo "[DC firstboot] OK: $_home (owner $_u:$_gname)"
done < /etc/passwd

# ── SAFETY NET PASSWORD: auto-unlock account con hash "!" prefix ──────────
# Se un servizio (pacman hook, CachyOS customize script, ecc.) ha lockato
# l'account dopo l'installazione Calamares, qui facciamo unlock forzato.
# NON cambia la password: solo rimuove il prefix "!" dallo shadow se il hash
# è valido ma locked. Se il hash è totalmente assente, salta (evita di
# sovrascrivere una password valida impostata dall'utente).
echo "[DC firstboot] Verifica lock account..."
_PW_CHANGED=0
while IFS=: read -r _u _h _rest; do
    # Utenti reali: root + UID>=1000
    if [ "$_u" = "root" ] || (getent passwd "$_u" | awk -F: '$3>=1000 && $3<65534 {exit 0} {exit 1}' 2>/dev/null); then
        case "$_h" in
            '!$'*|'!!$'*)
                # hash valido ma locked: unlock
                echo "[DC firstboot] unlock: $_u (hash era ${_h:0:4}...)"
                usermod -U "$_u" 2>/dev/null || passwd -u "$_u" 2>/dev/null || true
                _PW_CHANGED=$((_PW_CHANGED + 1))
                ;;
        esac
    fi
done < /etc/shadow
echo "[DC firstboot] Account unlocked: $_PW_CHANGED"

# ── openSUSE: setup snapper + grub2-snapper-plugin ──────────────────────
# Replica al primo boot il workflow manuale:
#   btrfs subvolume delete /.snapshots
#   snapper -c root create-config /
#   zypper install grub2-snapper-plugin
#   grub2-mkconfig -o /boot/grub2/grub.cfg
# Nota: con layout subvol=@ il menu GRUB snapshot resta vuoto (limite plugin
# openSUSE — vedi memory project_dc_opensuse_snapshot_boot_limitation),
# ma snapper+YaST funzionano out-of-the-box senza intervento utente.
if command -v snapper >/dev/null 2>&1 && [ -f /etc/os-release ] && \
   grep -qiE 'opensuse|suse' /etc/os-release; then
    echo "[DC firstboot] openSUSE rilevato — setup snapper..."

    if [ ! -f /etc/snapper/configs/root ]; then
        # Rimuovi placeholder /.snapshots vuoto (snapper create-config lo ricrea)
        if [ -d /.snapshots ] && [ -z "$(ls -A /.snapshots 2>/dev/null)" ]; then
            btrfs subvolume delete /.snapshots 2>/dev/null \
                || rmdir /.snapshots 2>/dev/null || true
        fi
        if snapper -c root create-config / 2>&1; then
            echo "[DC firstboot] OK: snapper config 'root' creato"
            snapper -c root create -d "DistroClone baseline" 2>&1 || true
        else
            echo "[DC firstboot] WARN: snapper create-config fallito"
        fi
    else
        echo "[DC firstboot] snapper config 'root' già presente — skip"
    fi

    # Installa grub2-snapper-plugin se manca (richiede internet)
    if [ ! -x /etc/grub.d/80_suse_btrfs_snapshot ] && command -v zypper >/dev/null 2>&1; then
        if getent ahosts download.opensuse.org >/dev/null 2>&1; then
            echo "[DC firstboot] Installo grub2-snapper-plugin..."
            zypper --non-interactive install grub2-snapper-plugin 2>&1 \
                || echo "[DC firstboot] WARN: zypper install fallito"
            if [ -x /etc/grub.d/80_suse_btrfs_snapshot ] && command -v grub2-mkconfig >/dev/null 2>&1; then
                grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 \
                    && echo "[DC firstboot] OK: grub.cfg rigenerato"
            fi
        else
            echo "[DC firstboot] WARN: nessuna connessione — grub2-snapper-plugin saltato"
        fi
    fi

    # Abilita timer snapper (timeline + cleanup automatico)
    systemctl enable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
fi

# ── Arch family (CachyOS etc.): setup snapper + grub-btrfs ───────────────
# CachyOS ships snapper + snap-pac + grub-btrfs pre-configured. After clone:
#   - /etc/snapper/configs/root is preserved from the source rsync
#   - /.snapshots/* host snapshots have been purged
#   - we need to recreate a baseline snapshot and enable grub-btrfsd
# grub-btrfs reads the @snapshots subvolume and generates a GRUB submenu
# natively — no plugin required (unlike openSUSE snapper-grub-plugin).
if command -v snapper >/dev/null 2>&1 && [ -f /etc/os-release ] && \
   grep -qiE 'ID=(arch|cachyos|manjaro|endeavouros|garuda|arcolinux|artix)|ID_LIKE=.*arch' /etc/os-release; then
    echo "[DC firstboot] Arch family rilevato — setup snapper..."

    if [ ! -f /etc/snapper/configs/root ]; then
        # Config mancante (clone non-CachyOS o pulizia aggressiva) — creala
        if [ -d /.snapshots ] && [ -z "$(ls -A /.snapshots 2>/dev/null)" ]; then
            btrfs subvolume delete /.snapshots 2>/dev/null \
                || rmdir /.snapshots 2>/dev/null || true
        fi
        if snapper -c root create-config / 2>&1; then
            echo "[DC firstboot] OK: snapper config 'root' creato (Arch)"
        else
            echo "[DC firstboot] WARN: snapper create-config fallito"
        fi
    else
        echo "[DC firstboot] snapper config 'root' già presente — preservata da rsync"
    fi

    # /.snapshots subvolume: se config presente ma la dir manca, creala.
    # Motivo: DistroClone.sh rsync esclude /.snapshots dal source (evita phantom
    # snapshot host) — sul target manca del tutto anche se Calamares copia @.
    # Senza questa dir, `snapper create` fallisce con "path://.snapshots errno:2".
    if [ -f /etc/snapper/configs/root ] && [ ! -d /.snapshots ]; then
        if command -v btrfs >/dev/null 2>&1; then
            btrfs subvolume create /.snapshots 2>/dev/null \
                && echo "[DC firstboot] /.snapshots subvolume creato (assente post-rsync)" \
                || { mkdir -p /.snapshots; echo "[DC firstboot] /.snapshots dir creata (btrfs subvolume fallito)"; }
        else
            mkdir -p /.snapshots
        fi
        chmod 750 /.snapshots 2>/dev/null || true
        chown root:root /.snapshots 2>/dev/null || true
    fi

    # Baseline snapshot (se non ce ne sono ancora)
    if [ -f /etc/snapper/configs/root ] && [ -d /.snapshots ]; then
        _dc_snap_count=$(snapper -c root list --disable-used-space 2>/dev/null | grep -cE '^[[:space:]]*[0-9]+' || echo 0)
        if [ "${_dc_snap_count:-0}" -lt 2 ]; then
            snapper -c root create -d "DistroClone baseline" 2>&1 || true
            echo "[DC firstboot] Baseline snapshot creato (Arch)"
        fi
    fi

    # grub-btrfs: abilita il daemon che rigenera il submenu GRUB ad ogni snapshot.
    # Upstream (Antynea/grub-btrfs) usa grub-btrfsd.service, CachyOS e altre
    # varianti usano grub-btrfs-snapper.service. Cerca entrambi.
    _dc_grubbtrfs_found=0
    for _gbsvc in grub-btrfs-snapper.service grub-btrfsd.service; do
        if systemctl cat "$_gbsvc" >/dev/null 2>&1; then
            systemctl enable --now "$_gbsvc" 2>/dev/null \
                && echo "[DC firstboot] OK: $_gbsvc enabled" \
                || echo "[DC firstboot] WARN: $_gbsvc enable fallito"
            _dc_grubbtrfs_found=1
            break
        fi
    done
    if [ "$_dc_grubbtrfs_found" -eq 0 ]; then
        echo "[DC firstboot] grub-btrfs daemon non installato — snapshot submenu GRUB non disponibile"
    fi

    # Rigenera grub.cfg: se grub-btrfs è installato, aggiunge il submenu snapshot
    if command -v grub-mkconfig >/dev/null 2>&1 && [ -d /boot/grub ]; then
        grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -3
        echo "[DC firstboot] grub.cfg rigenerato"
    fi

    # Timer snapper (timeline + cleanup automatico)
    for _t in snapper-timeline.timer snapper-cleanup.timer; do
        systemctl cat "$_t" >/dev/null 2>&1 && \
            systemctl enable --now "$_t" 2>/dev/null || true
    done
fi

touch /var/lib/distroClone-firstboot-done
echo "[DC firstboot] Completato"
FBEOF
chmod 755 /usr/local/bin/dc-firstboot.sh

mkdir -p /etc/systemd/system
cat > /etc/systemd/system/dc-firstboot.service << 'SVCEOF'
[Unit]
Description=DistroClone first-boot setup (home dirs + openSUSE snapper)
ConditionPathExists=!/var/lib/distroClone-firstboot-done
After=local-fs.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dc-firstboot.sh
RemainAfterExit=yes
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
SVCEOF
# MAI usare systemctl in chroot (può bloccarsi senza dbus) — solo symlink manuali
mkdir -p /etc/systemd/system/multi-user.target.wants 2>/dev/null || true
ln -sf /etc/systemd/system/dc-firstboot.service \
       /etc/systemd/system/multi-user.target.wants/dc-firstboot.service 2>/dev/null || true
echo "OK: dc-firstboot.service installato (safety net per /home)"

# ── Pulizia fstab: rimuovi entry /home errate (senza subvol su btrfs) ─────
# Se il modulo fstab C++ o il squashfs sorgente ha lasciato un entry /home
# btrfs senza subvol=@/home, al boot monta il top-level btrfs su /home
# nascondendo la dir reale dentro @. Rimuoviamo queste entry errate.
if [ -f /etc/fstab ]; then
    # Rileva se root è btrfs con subvol=@
    _fstab_root_opts="$(awk '$2=="/" {print $4}' /etc/fstab 2>/dev/null | head -1)"
    if echo "$_fstab_root_opts" | grep -q 'subvol=@'; then
        # Root usa subvol=@ — se /home NON ha subvol=@/home, rimuovilo
        _home_line="$(grep -E '^UUID=.*[[:space:]]/home[[:space:]]' /etc/fstab 2>/dev/null)"
        if [ -n "$_home_line" ] && ! echo "$_home_line" | grep -q 'subvol=@/home'; then
            echo "WARN: fstab ha /home btrfs senza subvol=@/home — rimuovo (nasconde @/home)"
            sed -i '/^UUID=.*[[:space:]]\/home[[:space:]]/d' /etc/fstab
        fi
    fi
fi

# ── Rimuovi autologin residuo da TUTTI i display manager ──────────────────
# Il squashfs contiene l'autologin del sistema live. remove-live-user rimuove
# solo il drop-in DistroClone, ma il sistema host potrebbe avere autologin
# in /etc/sddm.conf, altri drop-in, lightdm.conf, gdm custom.conf.
# Questa è la pulizia FINALE (dopo il modulo displaymanager di Calamares).
echo ""
echo "=== Rimozione autologin residuo ==="

# SDDM: rimuovi [Autologin] da TUTTI i file di configurazione
for _sddm_conf in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [ -f "$_sddm_conf" ] || continue
    if grep -qi '\[Autologin\]' "$_sddm_conf" 2>/dev/null; then
        # Rimuovi l'intera sezione [Autologin] fino alla prossima sezione o fine file
        sed -i '/^\[Autologin\]/,/^\[/{/^\[Autologin\]/d;/^\[/!d;}' "$_sddm_conf"
        echo "  SDDM: rimosso [Autologin] da $_sddm_conf"
    fi
done
rm -f /etc/sddm.conf.d/autologin.conf 2>/dev/null || true

# LightDM
if [ -f /etc/lightdm/lightdm.conf ]; then
    sed -i '/^autologin-user=/d;/^autologin-user-timeout=/d;/^autologin-session=/d' \
        /etc/lightdm/lightdm.conf 2>/dev/null || true
    echo "  LightDM: pulito"
fi
rm -f /etc/lightdm/lightdm.conf.d/50-distroClone-autologin.conf 2>/dev/null || true

# GDM
for _gdm_conf in /etc/gdm/custom.conf /etc/gdm3/custom.conf; do
    [ -f "$_gdm_conf" ] || continue
    sed -i '/^AutomaticLoginEnable=/d;/^AutomaticLogin=/d;/^TimedLoginEnable=/d' \
        "$_gdm_conf" 2>/dev/null || true
    echo "  GDM: pulito $_gdm_conf"
done

echo "OK: autologin rimosso"

# ── Fix /boot/loader → /boot/efi/loader (openSUSE EFI) ───────────────────
# Il squashfs estrae /boot/loader sulla partizione boot (ext4). Ma openSUSE
# con EFI vuole /loader sulla ESP montata a /boot/efi. Se /boot/efi è montato
# e /boot/loader esiste ma /boot/efi/loader no, spostiamo.
if mountpoint -q /boot/efi 2>/dev/null || [ -d /boot/efi/EFI ]; then
    if [ -d /boot/loader ] && [ ! -d /boot/efi/loader ]; then
        echo "Fix: sposto /boot/loader → /boot/efi/loader (ESP)"
        cp -a /boot/loader /boot/efi/loader 2>/dev/null || true
        rm -rf /boot/loader 2>/dev/null || true
        echo "  OK: /boot/efi/loader pronto"
    elif [ -d /boot/loader ] && [ -d /boot/efi/loader ]; then
        echo "Fix: /boot/efi/loader già presente — merge da /boot/loader"
        cp -a /boot/loader/. /boot/efi/loader/ 2>/dev/null || true
        rm -rf /boot/loader 2>/dev/null || true
    fi
fi

# ── Verifica finale mkinitcpio.conf (Arch/CachyOS) ────────────────────────
echo ""
echo "=== mkinitcpio.conf check ==="
if [ -f /etc/mkinitcpio.conf ]; then
    if grep -q 'archiso' /etc/mkinitcpio.conf; then
        echo "WARN: hook archiso ancora presenti — correggo"
        for _hook in archiso_loop_mnt archiso_pxe_common archiso_pxe_nbd \
        archiso_pxe_http archiso_pxe_nfs archiso_shutdown archiso_kms; do
            sed -i "s/ *${_hook}//g" /etc/mkinitcpio.conf
        done
        sed -i 's/ *archiso / /g' /etc/mkinitcpio.conf
        sed -i 's/ *archiso)/)/g' /etc/mkinitcpio.conf
        if ! grep -q 'autodetect' /etc/mkinitcpio.conf; then
            sed -i 's/^HOOKS=(\(.*\)udev /HOOKS=(\1udev autodetect modconf kms /' \
            /etc/mkinitcpio.conf
        fi
        sed -i 's/  */ /g; s/( /(/; s/ )/)/' /etc/mkinitcpio.conf
        echo "HOOKS dopo fix:"
        grep "^HOOKS=" /etc/mkinitcpio.conf
        echo "Rigenero initramfs..."
        _PRESET_FILE="$(compgen -G '/etc/mkinitcpio.d/*.preset' 2>/dev/null | head -n 1)"
        if [ -n "$_PRESET_FILE" ]; then
            _PRESET="$(basename "$_PRESET_FILE" .preset)"
            mkinitcpio -P 2>&1 | tail -5 || mkinitcpio -p "$_PRESET" 2>&1 | tail -5
            echo " -> initramfs rigenerato con preset $_PRESET"
        else
            _KFILE="$(compgen -G '/boot/vmlinuz-*' 2>/dev/null | head -n 1)"
            if [ -n "$_KFILE" ]; then
                _KVER="$(basename "$_KFILE" | sed 's/^vmlinuz-//')"
                mkinitcpio -c /etc/mkinitcpio.conf -k "$_KFILE" \
                    -g "/boot/initramfs-${_KVER}.img" 2>&1 | tail -5
                echo " -> initramfs rigenerato (fallback kernel $_KVER)"
            else
                echo " -> SKIP: nessun kernel trovato"
            fi
        fi
    else
        echo "OK: nessun hook archiso"
    fi
fi

# ── Mount unit cleanup ─────────────────────────────────────────────────────
echo ""
echo "=== Mount unit cleanup ==="
for _MU in \
/etc/systemd/system/home.mount \
/usr/lib/systemd/system/home.mount \
/lib/systemd/system/home.mount \
/etc/systemd/system/etc-pacman.d-gnupg.mount \
/usr/lib/systemd/system/etc-pacman.d-gnupg.mount \
/lib/systemd/system/etc-pacman.d-gnupg.mount; do
    if [ -e "$_MU" ]; then
        rm -f "$_MU"
        echo "WARN: rimosso residuo $_MU"
    fi
done
# Mask con symlink manuali (MAI systemctl in chroot — si blocca senza dbus)
mkdir -p /etc/systemd/system
ln -sf /dev/null /etc/systemd/system/home.mount 2>/dev/null || true
ln -sf /dev/null /etc/systemd/system/etc-pacman.d-gnupg.mount 2>/dev/null || true
echo "  MASKED: home.mount, etc-pacman.d-gnupg.mount"

# ── fstab: rimuovi tmpfs/overlay su /home (artefatti live) ────────────────
if [ -f /etc/fstab ]; then
    if grep -qE '^[[:space:]]*tmpfs[[:space:]]+/home[[:space:]]' /etc/fstab; then
        echo "WARN: tmpfs /home in /etc/fstab — rimuovo"
        sed -i '/^[[:space:]]*tmpfs[[:space:]]\+\/home[[:space:]]/d' /etc/fstab
    fi
    if grep -qE '^[[:space:]]*(overlay|aufs|unionfs)[[:space:]]+/home[[:space:]]' /etc/fstab; then
        echo "WARN: overlay /home in /etc/fstab — rimuovo"
        sed -i '/^[[:space:]]*\(overlay\|aufs\|unionfs\)[[:space:]]\+\/home[[:space:]]/d' /etc/fstab
    fi
fi

# daemon-reload/reset-failed: skip in chroot (nessun systemd in esecuzione)

# ── Arch/CachyOS ONLY: rimuovi live user ─────────────────────────────────
if command -v pacman >/dev/null 2>&1; then
    _ARCH_LU="${_LIVE_USER:-archie}"
    _ARCH_N="$(awk -F: '$3>=1000 && $3<65534{n++} END{print n+0}' /etc/passwd)"
    echo ""
    echo "Arch live-user removal: utente=${_ARCH_LU} uid1000_count=${_ARCH_N}"
    if [ "${_ARCH_N}" -ge 2 ] && id "${_ARCH_LU}" >/dev/null 2>&1; then
        _ARCH_H="$(getent passwd "${_ARCH_LU}" | cut -d: -f6)"
        userdel "${_ARCH_LU}" 2>/dev/null || \
            sed -i "/^${_ARCH_LU}:/d" /etc/passwd /etc/shadow /etc/group 2>/dev/null || true
        [ -n "${_ARCH_H}" ] && [ "${_ARCH_H}" != "/" ] && [ "${_ARCH_H}" != "/root" ] && \
            rm -rf "${_ARCH_H}" 2>/dev/null || true
        rm -f "/var/lib/AccountsService/users/${_ARCH_LU}" 2>/dev/null || true
        rm -f /etc/sddm.conf.d/dc-hide-live-user.conf 2>/dev/null || true
        rm -f /var/lib/sddm/state.conf 2>/dev/null || true
        echo "Arch: live user ${_ARCH_LU} rimosso (home=${_ARCH_H:-n/a})"
    else
        echo "Arch: SKIP live user removal (utenti_uid1000=${_ARCH_N})"
    fi
fi

echo ""
echo "=== Fine post-users ==="
POSTUSERSCRIPT
chmod 755 /usr/local/bin/dc-post-users.sh

write_shellprocess_conf /etc/calamares/modules/dc-post-users.conf false 60 \
/usr/local/bin/dc-post-users.sh

echo "[DC] ✓ dc-post-users configurato (diagnostica + fallback password)"

# =============================================================================
# 9. SETTINGS.CONF — delegato al modulo famiglia
# =============================================================================
echo "[9/9] settings.conf → sequenza [$DC_FAMILY]"
dc_settings_conf


echo ""
echo "══════════════════════════════════════════════════════"
echo " ✓ Calamares configuring for [$DC_FAMILY]"
echo " ✓ Branding: $BRANDING_ID"
echo " ✓ PKG backend: $PKG_BACKEND"
echo " ✓ Modules: $CAL_MODULES"
echo " ✓ Squashfs: $SQUASHFS_PATH"
echo "══════════════════════════════════════════════════════"
