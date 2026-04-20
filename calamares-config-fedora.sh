#!/bin/bash
# =============================================================================
# calamares-config-fedora.sh — Modulo famiglia Fedora/openSUSE
# =============================================================================
# Sourced da calamares-config.sh (orchestratore).
# Gestisce anche DC_FAMILY=opensuse (stessa struttura dracut/grub2).
# Definisce le funzioni: dc_set_paths, dc_users_conf, dc_remove_live_user,
#                        dc_configure_family, dc_settings_conf
# =============================================================================

dc_set_paths() {
    CAL_MODULES="/usr/lib64/calamares/modules"
    [ -d "/usr/lib/calamares/modules" ] && CAL_MODULES="/usr/lib/calamares/modules"
    PKG_BACKEND="dnf"
    GRUB_CMD="grub2-install"
    GRUB_CFG_CMD="grub2-mkconfig -o /boot/grub2/grub.cfg"
    SQUASHFS_PATH="/run/initramfs/live/LiveOS/squashfs.img"

    # openSUSE usa zypper e grub2 (stessa struttura Fedora)
    if [ "$DC_FAMILY" = "opensuse" ]; then
        PKG_BACKEND="zypper"
    fi

    # find-squashfs helper + aggiornamento SQUASHFS_PATH
    cat > /usr/local/bin/distroClone-find-squashfs.sh << 'SQFSCRIPT'
#!/bin/bash
for _p in \
    /run/initramfs/live/LiveOS/squashfs.img \
    /run/initramfs/live/live/filesystem.squashfs \
    /run/initramfs/livedev/LiveOS/squashfs.img \
    /run/live/medium/LiveOS/squashfs.img \
    /dev/disk/by-label/FEDORA-LIVE
do
    [ -e "$_p" ] && echo "$_p" && exit 0
done

_sqfs=$(grep -o '[^ ]*/squashfs\.img\|[^ ]*/filesystem\.squashfs' /proc/mounts 2>/dev/null | head -1)
[ -n "$_sqfs" ] && echo "$_sqfs" && exit 0
exit 1
SQFSCRIPT
    chmod +x /usr/local/bin/distroClone-find-squashfs.sh

    _REAL_SQ=$(/usr/local/bin/distroClone-find-squashfs.sh 2>/dev/null) || true
    if [ -n "$_REAL_SQ" ] && [ "$_REAL_SQ" != "$SQUASHFS_PATH" ]; then
        echo "  [INFO] squashfs trovato in: $_REAL_SQ (aggiorno da $SQUASHFS_PATH)"
        SQUASHFS_PATH="$_REAL_SQ"
    fi

    # ── Diagnostica: elenca moduli C++ disponibili ──────────────────────────
    echo "  Moduli in ${CAL_MODULES}:"
    ls "${CAL_MODULES}/" 2>/dev/null | tr '\n' ' ' || echo "(vuoto)"
    echo
    for _altmod in "/usr/lib/calamares/modules" "/usr/lib64/calamares/modules"; do
        [ "$_altmod" = "$CAL_MODULES" ] && continue
        [ -d "$_altmod" ] && echo "  Moduli in ${_altmod}: $(ls "$_altmod/" 2>/dev/null | tr '\n' ' ')" && echo
    done

    # ── Rileva moduli C++ critici (usa module.desc, non solo dir) ─────────
    # Senza partition → niente UI partizionamento
    # Senza mount/unpackfs → fallback shellprocess (hybrid o full)
    HAS_PARTITION_MODULE=0
    for _pmod in \
        "${CAL_MODULES}/partition" \
        "/usr/lib/calamares/modules/partition" \
        "/usr/lib64/calamares/modules/partition"; do
        if [ -f "$_pmod/module.desc" ]; then
            HAS_PARTITION_MODULE=1
            echo "  ✓ partition module.desc trovato in: $_pmod"
            break
        fi
    done

    HAS_MOUNT_MODULE=0
    for _mmod in \
        "${CAL_MODULES}/mount" \
        "/usr/lib/calamares/modules/mount" \
        "/usr/lib64/calamares/modules/mount"; do
        if [ -f "$_mmod/module.desc" ]; then
            HAS_MOUNT_MODULE=1; break
        fi
    done

    HAS_UNPACKFS_MODULE=0
    for _umod in \
        "${CAL_MODULES}/unpackfs" \
        "/usr/lib/calamares/modules/unpackfs" \
        "/usr/lib64/calamares/modules/unpackfs"; do
        if [ -f "$_umod/module.desc" ]; then
            HAS_UNPACKFS_MODULE=1; break
        fi
    done

    echo "  partition module: ${HAS_PARTITION_MODULE}"
    echo "  mount module:     ${HAS_MOUNT_MODULE}"
    echo "  unpackfs module:  ${HAS_UNPACKFS_MODULE}"
}

# Override di settings_begin_sequence() (definita in calamares-config.sh).
# Tre livelli in base ai moduli C++ disponibili:
#   1. FULL C++: partition + mount + unpackfs → standard Calamares (Fedora, openSUSE con kpmcore)
#   2. HYBRID:   partition (UI erase/manual/encrypt) ma senza mount/unpackfs →
#                partition C++ per UI + exec, Python mountbridge per mount, shellprocess per extract
#   3. SHELLPROCESS: nessun modulo partition → selezione disco via yad, tutto shellprocess
settings_begin_sequence() {
    if [ "${HAS_PARTITION_MODULE:-0}" -eq 1 ] && \
       [ "${HAS_MOUNT_MODULE:-0}" -eq 1 ] && \
       [ "${HAS_UNPACKFS_MODULE:-0}" -eq 1 ]; then
        # ── FULL C++: tutti i moduli disponibili ─────────────────────────────
        echo "[DC] Sequenza: FULL C++ (partition + mount + unpackfs)"
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
      - shellprocess@dc-btrfs-setup
      - unpackfs
      - shellprocess@remove-live-user
      - machineid
      - fstab
      - locale
      - keyboard
EOF
    elif [ "${HAS_PARTITION_MODULE:-0}" -eq 1 ]; then
        # ── HYBRID: partition C++ per UI, shellprocess per mount/extract ──────
        # Il modulo partition C++ in exec crea/formatta le partizioni e scrive
        # le info in GlobalStorage. Il modulo Python "mountbridge" legge
        # GlobalStorage, monta le partizioni, e scrive dc-install-info.env.
        echo "[DC] Sequenza: HYBRID (partition C++ UI + shellprocess mount/extract)"
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
      - mountbridge
      - shellprocess@dc-btrfs-setup
      - shellprocess@extract-squashfs
      - shellprocess@remove-live-user
      - shellprocess@write-machine-id
      - shellprocess@write-fstab
      - locale
      - keyboard
EOF
    else
        # ── SHELLPROCESS: nessun modulo partition C++ ─────────────────────────
        echo "[DC] Sequenza: SHELLPROCESS (nessun modulo partition C++)"
        cat >> "${SETTINGS_FILE}" <<'EOF'
sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - users
      - summary

  - exec:
      - setrootmount
      - shellprocess@disk-setup
      - shellprocess@dc-btrfs-setup
      - shellprocess@extract-squashfs
      - shellprocess@remove-live-user
      - shellprocess@write-machine-id
      - shellprocess@write-fstab
      - locale
      - keyboard
EOF
    fi
}

dc_users_conf() {
    cat > /etc/calamares/modules/users.conf << 'USERS_STD'
---
defaultGroups:
  - name: users
    mustexist: true
  - audio
  - cdrom
  - dialout
  - floppy
  - video
  - plugdev
  - netdev
  - scanner
  - bluetooth
  - sudo
  - wheel

autologinGroup: autologin
doAutologin: false
sudoersGroup: sudo
setRootPassword: true
doReusePassword: true

passwordRequirements:
  nonempty: true
  minLength: 4
  maxLength: -1

allowWeakPasswords: true
allowWeakPasswordsDefault: true
userShell: /bin/bash
setUpHome: true
USERS_STD
}

dc_remove_live_user() {
# ══════════════════════════════════════════════════════════════════════════════
# FEDORA / OPENSUSE: dc-remove-live-user.sh = rimuovi live user
# ══════════════════════════════════════════════════════════════════════════════
install -Dm755 /dev/stdin /usr/local/bin/dc-remove-live-user.sh << 'RMSCRIPT'
#!/bin/bash
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"
echo "=== dc-remove-live-user $(date) ==="

_LU=$(cat /etc/distroClone-live-user 2>/dev/null | tr -d '[:space:]')
if [ -z "$_LU" ]; then
    echo "WARN: /etc/distroClone-live-user non trovato, skip"
    exit 0
fi

echo "Live user: ${_LU}"

# Rimuovi utente live da passwd/shadow/group
sed -i "/^${_LU}:/d" /etc/passwd  2>/dev/null || true
sed -i "/^${_LU}:/d" /etc/shadow  2>/dev/null || true

for _f in /etc/group /etc/gshadow; do
    [ -f "$_f" ] || continue
    sed -i \
        -e "s/:${_LU}$/:/" \
        -e "s/:${_LU},/:/g" \
        -e "s/,${_LU},/,/g" \
        -e "s/,${_LU}$//" \
        "$_f"
done
sed -i "/^${_LU}:/d" /etc/group   2>/dev/null || true
sed -i "/^${_LU}:/d" /etc/gshadow 2>/dev/null || true

rm -rf "/home/${_LU}" 2>/dev/null || true
mkdir -p /home

# ── Rimuovi TUTTI gli utenti host (UID >= 1000) dal sistema clonato ─────────
# Il squashfs contiene gli utenti dell'host originale (es. "edmond").
# Se l'utente sceglie lo stesso nome in Calamares, useradd fallisce con
# "user already exists" → la password digitata non viene mai applicata.
# Soluzione: pulire TUTTI gli utenti non-system PRIMA del modulo users.
echo "[DC] Pulizia utenti host (UID >= 1000):"
# Leggi la lista utenti PRIMA di modificare /etc/passwd (evita read+sed simultaneo)
_HOST_USERS=$(awk -F: '$3 >= 1000 && $3 < 65534 && $1 != "nobody" {print $1":"$6}' /etc/passwd 2>/dev/null)
for _entry in $_HOST_USERS; do
    _name="${_entry%%:*}"
    _home="${_entry#*:}"
    echo "  rimuovo: $_name (home=$_home)"
    sed -i "/^${_name}:/d" /etc/passwd  2>/dev/null || true
    sed -i "/^${_name}:/d" /etc/shadow  2>/dev/null || true
    sed -i "/^${_name}:/d" /etc/group   2>/dev/null || true
    sed -i "/^${_name}:/d" /etc/gshadow 2>/dev/null || true
    # Rimuovi dal membership di altri gruppi
    for _gf in /etc/group /etc/gshadow; do
        [ -f "$_gf" ] || continue
        sed -i \
            -e "s/:${_name}$/:/" \
            -e "s/:${_name},/:/g" \
            -e "s/,${_name},/,/g" \
            -e "s/,${_name}$//" \
            "$_gf" 2>/dev/null || true
    done
    # Rimuovi home (verrà ricreata dal modulo users di Calamares)
    if [ -n "$_home" ] && [ "$_home" != "/" ] && [ "$_home" != "/root" ]; then
        rm -rf "$_home" 2>/dev/null || true
    fi
    # Rimuovi AccountsService e mail spool
    rm -f "/var/lib/AccountsService/users/${_name}" 2>/dev/null || true
    rm -f "/var/spool/mail/${_name}" 2>/dev/null || true
done
echo "[DC] ✓ Utenti host rimossi — Calamares creerà utente fresco"

# Rimuovi artefatti live: bash/zsh/fish history, cache shell, clipboard
# Necessario perché il squashfs include i comandi della sessione live
for _hist in /root/.bash_history /root/.zsh_history /root/.ash_history \
             /root/.local/share/recently-used.xbel \
             /root/.config/fish/fish_history; do
    rm -f "$_hist" 2>/dev/null || true
done
# Tronca in caso di file aperti da processi
: > /root/.bash_history 2>/dev/null || true
# Rimuovi history da qualsiasi altra home utente nel sistema
for _hdir in /home/*/; do
    [ -d "$_hdir" ] || continue
    rm -f "${_hdir}.bash_history" "${_hdir}.zsh_history" \
          "${_hdir}.ash_history" 2>/dev/null || true
    rm -f "${_hdir}.local/share/recently-used.xbel" 2>/dev/null || true
    rm -f "${_hdir}.config/fish/fish_history" 2>/dev/null || true
done
echo "[DC] ✓ bash/shell history rimossa"

# Rimuovi autologin live dal display manager
sed -i "/^autologin-user=/d;/^autologin-user-timeout=/d;/^autologin-session=/d" \
    /etc/lightdm/lightdm.conf 2>/dev/null || true
rm -f /etc/lightdm/lightdm.conf.d/50-distroClone-autologin.conf 2>/dev/null || true
rm -f /etc/sddm.conf.d/autologin.conf 2>/dev/null || true
sed -i "/^AutomaticLoginEnable=/d;/^AutomaticLogin=/d;/^TimedLoginEnable=/d" \
    /etc/gdm/custom.conf /etc/gdm3/custom.conf 2>/dev/null || true

# Fix /etc/shadow permissions — safety net: il clone dal live potrebbe avere
# permessi sbagliati (000 o root:root). Senza 640 root:shadow, PAM non riesce
# a leggere gli hash per utenti non-root → "password errata" al login.
if ! getent group shadow >/dev/null 2>&1; then
    groupadd -g 42 shadow 2>/dev/null || groupadd shadow 2>/dev/null || true
fi
chown root:shadow /etc/shadow 2>/dev/null || true
chmod 640 /etc/shadow 2>/dev/null || true
echo "[DC] ✓ /etc/shadow → 640 root:shadow"

echo "[DC] ✓ Live user ${_LU} rimosso"
echo "=== Fine ==="
RMSCRIPT
}

dc_configure_family() {
    # Fix: sovrascrive partition.conf con /boot separato NON cifrato.
    # La versione shared in calamares-config.sh ha solo rootfs al 100% →
    # con LUKS, /boot finisce dentro il container LUKS → GRUB deve decifrare
    # (software PBKDF2, nessun AES-NI in contesto EFI) = 5 minuti in VM.
    # Con /boot separato (noEncrypt: true):
    #   - GRUB legge kernel da ext4 senza decifrare nulla (= veloce)
    #   - GRUB_ENABLE_CRYPTODISK=y NON necessario
    #   - Solo dracut chiede password una volta (AES-NI = secondi)
    # Fedora standard (Anaconda): SEMPRE /boot separato per questa ragione.
    # /boot è sempre ext4 (GRUB deve leggerlo prima del decrypt).
    # rootfs: propagate source / filesystem to target default.
    # Without `filesystem:` in rootfs layout, Calamares uses defaultFileSystemType
    # (honours the user's dropdown choice).
    local _DC_DEFAULT_FS="ext4"
    local _DC_SRC_ROOT_FS
    _DC_SRC_ROOT_FS=$(findmnt -no FSTYPE / 2>/dev/null | head -1)
    case "${_DC_SRC_ROOT_FS:-}" in
        btrfs|xfs|ext4) _DC_DEFAULT_FS="$_DC_SRC_ROOT_FS" ;;
    esac
    # Hardcoded fallback if detection fails
    [ "${DC_FAMILY:-}" = "opensuse" ] && [ "$_DC_DEFAULT_FS" = "ext4" ] && _DC_DEFAULT_FS="btrfs"
    cat > /etc/calamares/modules/partition.conf << PARTCONF_FED
---
efiSystemPartition: "/boot/efi"
efiSystemPartitionSize: 300M
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
  - name: "boot"
    filesystem: "ext4"
    mountPoint: "/boot"
    size: 1G
    minSize: 512M
    noEncrypt: true
  - name: "rootfs"
    filesystem: "${_DC_DEFAULT_FS}"
    mountPoint: "/"
    size: 100%
    minSize: 8G

# Layout subvolumi btrfs openSUSE TW standard.
# Il modulo partition C++ crea questi subvolumi quando il filesystem è btrfs.
# Per ext4/xfs vengono ignorati. Applicato solo nel path FULL C++ e HYBRID.
# Nel path SHELLPROCESS, disk-setup.sh li crea manualmente.
btrfsSubvolumes:
  - mountPoint: /
    subvolume: /@
  - mountPoint: /home
    subvolume: /@/home
  - mountPoint: /var
    subvolume: /@/var
  - mountPoint: /usr/local
    subvolume: /@/usr/local
  - mountPoint: /srv
    subvolume: /@/srv
  - mountPoint: /root
    subvolume: /@/root
  - mountPoint: /opt
    subvolume: /@/opt
  - mountPoint: /.snapshots
    subvolume: /@/.snapshots
PARTCONF_FED
    echo "[DC] ✓ partition.conf ${DC_FAMILY}: /boot ext4 noEncrypt + rootfs ${_DC_DEFAULT_FS}"

    cat > /usr/local/bin/distroClone-rebuild-initramfs.sh << 'RDSCRIPT'
#!/bin/bash
set +e

echo "[DC] Rebuild initramfs nel target..."

TARGET=""
for _mp in /tmp/calamares-root /mnt/target /target; do
    if mountpoint -q "$_mp" 2>/dev/null || [ -d "$_mp/etc" ]; then
        TARGET="$_mp"
        break
    fi
done

if [ -z "$TARGET" ]; then
    TARGET=$(awk '{print $2}' /proc/mounts 2>/dev/null | while read -r mp; do
        [ -f "$mp/etc/os-release" ] && [ "$mp" != "/" ] && echo "$mp" && break
    done)
fi

echo "[DC] Target mount: ${TARGET:-non trovato}"

if [ -z "$TARGET" ] || [ ! -d "$TARGET/lib/modules" ]; then
    echo "[DC] SKIP: target non trovato o lib/modules assente — initramfs già valido"
    exit 0
fi

rm -f "$TARGET/etc/dracut.conf.d/99-distroClone-live.conf" 2>/dev/null || true

KERNEL_VER=$(ls "$TARGET/lib/modules/" 2>/dev/null | sort -V | tail -1)
echo "[DC] Kernel nel target: ${KERNEL_VER:-non trovato}"

if [ -z "$KERNEL_VER" ]; then
    echo "[DC] SKIP: nessun kernel in $TARGET/lib/modules/"
    exit 0
fi

# ── Fix symlink kernel/initrd in /boot ──────────────────────────────────────
# openSUSE Tumbleweed (e Fedora 39+): il kernel è installato in
#   /usr/lib/modules/<kver>/vmlinuz
# con symlink:
#   /boot/vmlinuz-<kver> → ../usr/lib/modules/<kver>/vmlinuz
# Se /boot è partizione separata, il symlink punta FUORI dalla boot partition
# (verso la root partition). GRUB non può seguire symlink cross-partition →
#   "error: file `/vmlinuz-xxx' not found"
# Soluzione: sostituisci i symlink con copie del file reale.
_BOOT_SEPARATE=0
if mountpoint -q "$TARGET/boot" 2>/dev/null; then
    _BOOT_SEPARATE=1
    echo "[DC] /boot è partizione separata — risolvo symlink cross-partition"
fi

if [ "$_BOOT_SEPARATE" -eq 1 ]; then
    for _sym in "$TARGET"/boot/vmlinuz-* "$TARGET"/boot/vmlinuz \
                "$TARGET"/boot/initrd-*  "$TARGET"/boot/initrd \
                "$TARGET"/boot/Image-*; do
        [ -L "$_sym" ] || continue
        # Fix: readlink -f su symlink ASSOLUTI risolve sul HOST, non sul TARGET.
        # Soluzione: se il symlink è assoluto, prefissa con $TARGET.
        _raw_link=$(readlink "$_sym" 2>/dev/null)
        if [[ "${_raw_link}" == /* ]]; then
            # Symlink assoluto → prefissa con TARGET per restare nel filesystem target
            _real="${TARGET}${_raw_link}"
        else
            # Symlink relativo → readlink -f funziona correttamente
            _real=$(readlink -f "$_sym")
        fi
        if [ -f "$_real" ]; then
            rm -f "$_sym"
            cp "$_real" "$_sym"
            echo "[DC] ✓ Symlink risolto: $(basename "$_sym") ($(du -h "$_sym" | cut -f1))"
        else
            echo "[DC] WARN: symlink $(basename "$_sym") → target non trovato: $_real"
            # Ultimo tentativo: copia da /usr/lib/modules se disponibile
            _basename=$(basename "$_sym")
            _kver_from_name="${_basename#vmlinuz-}"
            if [ -f "$TARGET/usr/lib/modules/${_kver_from_name}/vmlinuz" ]; then
                rm -f "$_sym"
                cp "$TARGET/usr/lib/modules/${_kver_from_name}/vmlinuz" "$_sym"
                echo "[DC] ✓ Kernel copiato da /usr/lib/modules/${_kver_from_name}/vmlinuz"
            fi
        fi
    done

    # Verifica finale: il kernel DEVE essere un file reale (non symlink) sulla boot partition
    if [ -f "$TARGET/boot/vmlinuz-${KERNEL_VER}" ] && [ ! -L "$TARGET/boot/vmlinuz-${KERNEL_VER}" ]; then
        echo "[DC] ✓ Kernel presente (file reale): vmlinuz-${KERNEL_VER} ($(du -h "$TARGET/boot/vmlinuz-${KERNEL_VER}" | cut -f1))"
    elif [ -f "$TARGET/usr/lib/modules/${KERNEL_VER}/vmlinuz" ]; then
        # Symlink mancava o non risolto — copia manuale dal path canonico
        echo "[DC] Kernel non reale in /boot — copio da /usr/lib/modules/${KERNEL_VER}/vmlinuz"
        rm -f "$TARGET/boot/vmlinuz-${KERNEL_VER}"
        cp "$TARGET/usr/lib/modules/${KERNEL_VER}/vmlinuz" \
           "$TARGET/boot/vmlinuz-${KERNEL_VER}"
        echo "[DC] ✓ Kernel copiato: vmlinuz-${KERNEL_VER}"
    else
        echo "[DC] WARN: kernel vmlinuz-${KERNEL_VER} non trovato né in /boot né in /usr/lib/modules"
    fi
fi
echo "[DC] /boot contents: $(ls "$TARGET/boot/" 2>/dev/null | tr '\n' ' ')"

for _d in proc sys dev dev/pts run; do
    mkdir -p "$TARGET/$_d"
    mount --bind "/$_d" "$TARGET/$_d" 2>/dev/null || true
done

# Rileva se root è btrfs nel TARGET (per aggiungere modulo btrfs a dracut)
_DC_DRACUT_EXTRA_ADD=""
_DC_ROOT_FS=$(awk '$2=="/" && $1!="none" {print $3}' "$TARGET/etc/fstab" 2>/dev/null | head -1)
if [ "$_DC_ROOT_FS" = "btrfs" ]; then
    _DC_DRACUT_EXTRA_ADD="--add btrfs"
    echo "[DC] dracut: root è btrfs — aggiungo modulo btrfs"
fi

echo "[DC] Eseguo dracut nel target per kernel $KERNEL_VER..."
chroot "$TARGET" /bin/bash -c "
set +e
# Rimuovi TUTTI i conf live (DistroClone + openSUSE/Fedora/kiwi nativi)
rm -f /etc/dracut.conf.d/99-distroClone-live.conf 2>/dev/null || true
rm -f /etc/dracut.conf.d/*live* /etc/dracut.conf.d/*livecd* /etc/dracut.conf.d/*kiwi* 2>/dev/null || true
# Ricostruisci escludendo esplicitamente i moduli live:
#   dmsquash-live/dmsquash-live-ntfs = modulo live Fedora/RHEL
#   kiwi-live                        = modulo live openSUSE (dracut-kiwi-live pkg)
#   livenet                          = live boot da rete
# --no-hostonly: obbligatorio nel chroot — senza di esso dracut legge il conf
#   del live system (hostonly="yes") e genera initramfs per squashfs/overlayfs
#   anziché per il sistema installato (ext4), causando boot failure.
dracut --force \
    --no-hostonly \
    --omit 'dmsquash-live dmsquash-live-ntfs livenet kiwi-live' \
    $_DC_DRACUT_EXTRA_ADD \
    /boot/initramfs-${KERNEL_VER}.img ${KERNEL_VER} 2>&1
echo \"[DC] dracut exit: \$?\"
exit 0
" || true

for _d in dev/pts dev run sys proc; do
    umount -l "$TARGET/$_d" 2>/dev/null || true
done

echo "[DC] ✓ rebuild-initramfs completato"
exit 0
RDSCRIPT
    chmod +x /usr/local/bin/distroClone-rebuild-initramfs.sh

    write_shellprocess_conf /etc/calamares/modules/rebuild-initramfs.conf true 900 \
        /usr/local/bin/distroClone-rebuild-initramfs.sh

    # cleanup-live-conf: usa script per evitare systemctl in chroot (si blocca senza dbus)
    install -Dm755 /dev/stdin /usr/local/bin/dc-cleanup-live-conf.sh << 'CLEANLIVE'
#!/bin/bash
set +e
echo "=== dc-cleanup-live-conf ==="
rm -f /etc/dracut.conf.d/99-distroClone-live.conf 2>/dev/null || true
rm -f /etc/skel/Desktop/install-system.desktop 2>/dev/null || true
# Disabilita servizi live con symlink manuali (MAI systemctl in chroot)
mkdir -p /etc/systemd/system
for _svc in livesys.service livesys-late.service auditd.service; do
    ln -sf /dev/null "/etc/systemd/system/$_svc" 2>/dev/null || true
done
echo "  MASKED: livesys, livesys-late, auditd"
echo "=== cleanup-live-conf OK ==="
CLEANLIVE

    write_shellprocess_conf /etc/calamares/modules/cleanup-live-conf.conf false 60 \
        /usr/local/bin/dc-cleanup-live-conf.sh

    echo "[DC] ✓ cleanup-live-conf configurato"

    # ──────────────────────────────────────────────────────────────────────────
    # DC-FINAL-FIXES: ultimo script prima di umount — fix autologin e /boot/loader
    # Gira DOPO grubinstall, displaymanager, tutti i moduli. È l'ultima modifica
    # al filesystem del target prima dello smontaggio.
    # ──────────────────────────────────────────────────────────────────────────
    install -Dm755 /dev/stdin /usr/local/bin/dc-final-fixes.sh << 'FINALFIXES'
#!/bin/bash
set +e
echo "=== dc-final-fixes (post-grub, pre-umount) ==="

# ── 1. DISABILITA autologin su TUTTI i display manager ───────────────────
# Strategia: invece di cercare e rimuovere (può mancare qualche file),
# SCRIVI un override esplicito che disabilita l'autologin. I file in
# /etc/sddm.conf.d/ hanno priorità sui vendor defaults.
echo "[1] Disabilitazione autologin..."

# SDDM: scrivi override che azzera l'autologin (sovrascrive qualsiasi config)
rm -f /etc/sddm.conf.d/autologin.conf 2>/dev/null || true
mkdir -p /etc/sddm.conf.d 2>/dev/null || true
cat > /etc/sddm.conf.d/zz-dc-no-autologin.conf << 'NOAUTO'
# DistroClone: disabilita autologin post-installazione
[Autologin]
Relogin=false
User=
Session=
NOAUTO
echo "  SDDM: /etc/sddm.conf.d/zz-dc-no-autologin.conf creato"

# Rimuovi anche [Autologin] da /etc/sddm.conf (potrebbe avere precedenza)
if [ -f /etc/sddm.conf ]; then
    sed -i '/^\[Autologin\]/I,/^\[/{/^\[Autologin\]/Id;/^\[/!d;}' /etc/sddm.conf 2>/dev/null || true
    echo "  SDDM: pulito /etc/sddm.conf"
fi

# openSUSE sysconfig: rimuovi DISPLAYMANAGER_AUTOLOGIN se presente
if [ -f /etc/sysconfig/displaymanager ]; then
    sed -i 's/^DISPLAYMANAGER_AUTOLOGIN=.*/DISPLAYMANAGER_AUTOLOGIN=""/' \
        /etc/sysconfig/displaymanager 2>/dev/null || true
    sed -i 's/^DISPLAYMANAGER_PASSWORD_LESS_LOGIN=.*/DISPLAYMANAGER_PASSWORD_LESS_LOGIN="no"/' \
        /etc/sysconfig/displaymanager 2>/dev/null || true
    echo "  sysconfig: DISPLAYMANAGER_AUTOLOGIN svuotato"
fi

# LightDM: scrivi override
if [ -d /etc/lightdm ]; then
    for _lf in /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/*.conf; do
        [ -f "$_lf" ] || continue
        sed -i '/^autologin-user=/d;/^autologin-user-timeout=/d;/^autologin-session=/d' \
            "$_lf" 2>/dev/null || true
    done
    echo "  LightDM: pulito"
fi

# GDM: disabilita esplicitamente
for _gf in /etc/gdm/custom.conf /etc/gdm3/custom.conf; do
    [ -f "$_gf" ] || continue
    sed -i '/^AutomaticLoginEnable=/d;/^AutomaticLogin=/d;/^TimedLoginEnable=/d' \
        "$_gf" 2>/dev/null || true
    # Aggiungi disabilitazione esplicita nella sezione [daemon]
    if grep -q '^\[daemon\]' "$_gf" 2>/dev/null; then
        sed -i '/^\[daemon\]/a AutomaticLoginEnable=False' "$_gf" 2>/dev/null || true
    fi
    echo "  GDM: disabilitato in $_gf"
done
echo "  OK: autologin disabilitato su tutti i DM"

# ── 2. Sposta /boot/loader → /boot/efi/loader (openSUSE EFI) ────────────
echo "[2] Fix /boot/loader..."
if [ -d /boot/efi/EFI ] || mountpoint -q /boot/efi 2>/dev/null; then
    if [ -d /boot/loader ]; then
        mkdir -p /boot/efi/loader 2>/dev/null || true
        cp -a /boot/loader/. /boot/efi/loader/ 2>/dev/null || true
        rm -rf /boot/loader 2>/dev/null || true
        echo "  OK: /boot/loader spostato in /boot/efi/loader"
    else
        echo "  SKIP: /boot/loader non presente"
    fi
else
    echo "  SKIP: /boot/efi non disponibile (sistema BIOS?)"
fi

# ── 3. Rimuovi initramfs live leftover ──────────────────────────────────
# L'estrazione squashfs copia anche gli initramfs del sistema live (suffisso
# "-live.img" / "-live") in /boot. Non sono referenziati da nessuna BLS entry
# né da grub.cfg → solo spreco di spazio (50-200 MB). Rimuovi solo pattern
# ESPLICITI: mai toccare il kernel versionato (-default) né `vmlinuz` plain.
echo "[3] Cleanup initramfs live leftover..."
_removed=0
for _f in /boot/initramfs-*-live.img /boot/initrd-*-live.img /boot/initramfs-*-live /boot/initrd-*-live; do
    [ -e "$_f" ] || continue
    if rm -f "$_f" 2>/dev/null; then
        _removed=$((_removed+1))
        echo "  rimosso: $(basename "$_f")"
    fi
done
echo "  OK: $_removed file live rimossi"

echo "=== dc-final-fixes OK ==="
exit 0
FINALFIXES

    write_shellprocess_conf /etc/calamares/modules/dc-final-fixes.conf false 60 \
        /usr/local/bin/dc-final-fixes.sh

    echo "[DC] ✓ dc-final-fixes configurato (autologin + boot/loader, post-grub)"

    # ──────────────────────────────────────────────────────────────────────────
    # DC-BTRFS-SETUP: crea subvolumi btrfs openSUSE se mancanti.
    # Gira DOPO mount/partition e PRIMA di unpackfs/extract-squashfs.
    # Funziona in TUTTI i path (FULL C++, HYBRID, SHELLPROCESS).
    # Se il modulo partition C++ non crea subvolumi (btrfsSubvolumes ignorato),
    # questo script li crea manualmente e remonta con subvol=@.
    # Se i subvolumi esistono già (da disk-setup o btrfsSubvolumes), verifica solo.
    # dontChroot: true — lavora dall'esterno sul target montato.
    # ──────────────────────────────────────────────────────────────────────────
    install -Dm755 /dev/stdin /usr/local/bin/dc-btrfs-setup.sh << 'BTRFSSETUP'
#!/bin/bash
set +e
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"
echo "=== dc-btrfs-setup ==="

# Trova target mount point
TARGET=""
for _mp in /tmp/calamares-root /tmp/calamares-root-*; do
    mountpoint -q "$_mp" 2>/dev/null && TARGET="$_mp" && break
done
[ -z "$TARGET" ] && { echo "SKIP: target non montato"; exit 0; }

# Verifica se btrfs
_FS=$(findmnt -n -o FSTYPE "$TARGET" 2>/dev/null | head -1)
[ "$_FS" != "btrfs" ] && { echo "SKIP: root=$_FS (non btrfs)"; exit 0; }

_DEV=$(findmnt -n -o SOURCE "$TARGET" 2>/dev/null | head -1)
# Rimuovi subvol suffix se presente (findmnt può tornare /dev/sda3[/@])
_DEV="${_DEV%%\[*}"
echo "Target=$TARGET  device=$_DEV  fstype=$_FS"

# ── Controlla se @ esiste già ─────────────────────────────────────────────
_HAS_AT=0
btrfs subvolume list "$TARGET" 2>/dev/null | grep -qE '(^|\s)path @$' && _HAS_AT=1

if [ "$_HAS_AT" -eq 1 ]; then
    echo "@ subvolume già presente"
    # Verifica che anche i nested esistano
    _TMPMT=$(mktemp -d /tmp/dc-btrfs-XXXXXX)
    mount -o subvolid=5 "$_DEV" "$_TMPMT" 2>/dev/null || mount "$_DEV" "$_TMPMT" 2>/dev/null
    if mountpoint -q "$_TMPMT" 2>/dev/null; then
        for _sv in var srv root opt home .snapshots; do
            if ! btrfs subvolume list "$_TMPMT" 2>/dev/null | grep -qE "path @/${_sv}\$"; then
                btrfs subvolume create "$_TMPMT/@/$_sv" 2>/dev/null && echo "  Creato: @/$_sv"
            fi
        done
        if ! btrfs subvolume list "$_TMPMT" 2>/dev/null | grep -qE 'path @/usr/local$'; then
            mkdir -p "$_TMPMT/@/usr" 2>/dev/null || true
            btrfs subvolume create "$_TMPMT/@/usr/local" 2>/dev/null && echo "  Creato: @/usr/local"
        fi
        umount "$_TMPMT" 2>/dev/null
    fi
    rmdir "$_TMPMT" 2>/dev/null || true

    # Se montato senza subvol=@, remonta
    if ! findmnt -n -o OPTIONS "$TARGET" 2>/dev/null | grep -qE 'subvol=/?@(,|$)'; then
        echo "WARN: montato senza subvol=@ — remount necessario"
    else
        echo "OK: montato con subvol=@"
        btrfs subvolume list "$TARGET" 2>/dev/null
        echo "=== dc-btrfs-setup OK (verificato) ==="
        exit 0
    fi
fi

# ── Crea @ e subvolumi, poi remonta ──────────────────────────────────────
echo "Creazione layout btrfs openSUSE..."

# Salva device boot/efi per remontarli dopo
_BOOT_DEV=$(findmnt -rn -o SOURCE "$TARGET/boot" 2>/dev/null | head -1)
_EFI_DEV=$(findmnt -rn -o SOURCE "$TARGET/boot/efi" 2>/dev/null | head -1)
echo "  boot_dev=${_BOOT_DEV:-none}  efi_dev=${_EFI_DEV:-none}"

# Smonta tutto dal target (ordine: più profondo prima)
umount "$TARGET/boot/efi" 2>/dev/null || true
# Lazy unmount in ordine: dal più profondo al meno profondo.
# -l = lazy: rimuove dal namespace immediatamente anche se ci sono processi
# con file aperti (Calamares ha CWD o fd dentro → senza -l → EBUSY).
sync
# Prima smonta mount innestati (efivarfs dentro sys, dev/pts dentro dev)
umount -l "$TARGET/sys/firmware/efi/efivars" 2>/dev/null || true
umount -l "$TARGET/dev/pts"  2>/dev/null || true
umount -l "$TARGET/dev"      2>/dev/null || true
umount -l "$TARGET/run/udev" 2>/dev/null || true
umount -l "$TARGET/run"      2>/dev/null || true
umount -l "$TARGET/sys"      2>/dev/null || true
umount -l "$TARGET/proc"     2>/dev/null || true
umount -l "$TARGET/boot/efi" 2>/dev/null || true
umount -l "$TARGET/boot"     2>/dev/null || true
# Ora smonta il target root (lazy: si smonta anche se Calamares ha cwd dentro)
umount -l "$TARGET" 2>/dev/null
echo "  Smontaggio completato"

# Monta top-level btrfs su path temporaneo e crea subvolumi
_TMPMT=$(mktemp -d /tmp/dc-btrfs-XXXXXX)
mount "$_DEV" "$_TMPMT" 2>/dev/null || \
    mount -o subvolid=5 "$_DEV" "$_TMPMT" 2>/dev/null || \
    { echo "ERROR: mount top-level fallito"; rmdir "$_TMPMT"; exit 1; }

if [ "$_HAS_AT" -eq 0 ]; then
    btrfs subvolume create "$_TMPMT/@" || { umount "$_TMPMT"; rmdir "$_TMPMT"; exit 1; }
    echo "  Creato: @"
fi

for _sv in var srv root opt home .snapshots; do
    if ! btrfs subvolume list "$_TMPMT" 2>/dev/null | grep -qE "path @/${_sv}\$"; then
        btrfs subvolume create "$_TMPMT/@/$_sv" 2>/dev/null && echo "  Creato: @/$_sv"
    fi
done
if ! btrfs subvolume list "$_TMPMT" 2>/dev/null | grep -qE 'path @/usr/local$'; then
    mkdir -p "$_TMPMT/@/usr" 2>/dev/null || true
    btrfs subvolume create "$_TMPMT/@/usr/local" 2>/dev/null && echo "  Creato: @/usr/local"
fi

echo "Subvolumi:"
btrfs subvolume list "$_TMPMT"
umount "$_TMPMT"; rmdir "$_TMPMT" 2>/dev/null || true

# Rimonta target con subvol=@
if ! mount -o subvol=@ "$_DEV" "$TARGET" 2>/dev/null; then
    echo "Primo tentativo fallito, riprovo..."
    sleep 1
    mount -o subvol=@ "$_DEV" "$TARGET" || { echo "ERROR: remount subvol=@ fallito"; exit 1; }
fi
echo "OK: $TARGET rimontato con subvol=@"

# Rimonta boot e EFI (necessari per GRUB e fstab)
if [ -n "$_BOOT_DEV" ]; then
    mkdir -p "$TARGET/boot"
    mount "$_BOOT_DEV" "$TARGET/boot" && echo "  boot rimontato" || echo "  WARN: boot mount fallito"
    if [ -n "$_EFI_DEV" ]; then
        mkdir -p "$TARGET/boot/efi"
        mount "$_EFI_DEV" "$TARGET/boot/efi" && echo "  efi rimontato" || echo "  WARN: efi mount fallito"
    fi
fi

# Rimonta VFS (necessari per moduli C++ successivi: machineid, fstab, locale...)
for _d in proc sys dev dev/pts run; do
    mkdir -p "$TARGET/$_d" 2>/dev/null || true
    case "$_d" in
        proc)    mount -t proc    proc    "$TARGET/proc"    2>/dev/null || true ;;
        sys)     mount -t sysfs   sysfs   "$TARGET/sys"     2>/dev/null || true ;;
        dev)     mount --bind     /dev    "$TARGET/dev"     2>/dev/null || true ;;
        dev/pts) mount --bind     /dev/pts "$TARGET/dev/pts" 2>/dev/null || true ;;
        run)     mount -t tmpfs   tmpfs   "$TARGET/run"     2>/dev/null || true ;;
    esac
done

echo "Mount finale:"
findmnt -R "$TARGET" 2>/dev/null | head -20
echo "=== dc-btrfs-setup OK ==="
exit 0
BTRFSSETUP

    write_shellprocess_conf /etc/calamares/modules/dc-btrfs-setup.conf true 120 \
        /usr/local/bin/dc-btrfs-setup.sh

    echo "[DC] ✓ dc-btrfs-setup configurato (subvolumi btrfs, pre-extraction)"

    # ──────────────────────────────────────────────────────────────────────────
    # DISK-SETUP: script alternativo quando il modulo partition C++ è assente
    # (openSUSE: usa YaST nativamente → Calamares può essere senza kpmcore plugin)
    # Gestisce: selezione disco, partitioning, formattazione, mount su /tmp/calamares-root
    # ──────────────────────────────────────────────────────────────────────────
    install -Dm755 /dev/stdin /usr/local/bin/dc-disk-setup.sh << 'DISKSETUP'
#!/bin/bash
set +e

# PATH esplicito: Calamares shellprocess ha PATH ridotto (manca /usr/sbin, /sbin)
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"

# NON usare "exec > file 2>&1": Calamares shellprocess cattura stdout/stderr
# direttamente. Con exec redirect il processo scrive nel file ma Calamares vede
# zero output e riporta "There was no output from the command" con exit code 1.

echo "=== DistroClone disk-setup $(date) ==="
echo "Running as: $(id)"
echo "PATH: $PATH"
echo "parted: $(command -v parted 2>/dev/null || echo 'NON TROVATO')"

# Trova dischi interi (non partizioni, non loop, non ROM)
_DISK_LIST=""
while IFS= read -r _line; do
    _dev=$(echo "$_line" | awk '{print $1}')
    _size=$(echo "$_line" | awk '{print $2}')
    _type=$(echo "$_line" | awk '{print $3}')
    if [ "$_type" = "disk" ]; then
        _DISK_LIST="${_DISK_LIST}/dev/${_dev}!${_size}!true\n"
    fi
done < <(lsblk -ndo NAME,SIZE,TYPE 2>/dev/null)

# Fallback a device noti
if [ -z "$_DISK_LIST" ]; then
    for _d in /dev/vda /dev/sda /dev/sdb /dev/nvme0n1; do
        [ -b "$_d" ] && _DISK_LIST="${_DISK_LIST}${_d}!$(lsblk -ndo SIZE "$_d" 2>/dev/null)!true\n"
    done
fi

echo "Dischi disponibili:"; printf "%b" "$_DISK_LIST"

if [ -z "$_DISK_LIST" ]; then
    echo "ERROR: nessun disco trovato"; exit 1
fi

TARGET_DISK=$(printf "%b" "$_DISK_LIST" | head -1 | cut -d'!' -f1)

# Selezione interattiva via yad (se disponibile)
if command -v yad >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
    _SEL=$(printf "%b" "$_DISK_LIST" | \
        yad --list \
            --title="DistroClone — Disco target" \
            --text="ATTENZIONE: il disco verrà formattato e tutti i dati eliminati.\nScegli il disco di destinazione:" \
            --column="Seleziona" --column="Disco" --column="Dimensione" \
            --radiolist \
            --button="Installa:0" --button="Annulla:1" \
            --width=520 --height=350 2>/dev/null | head -1 | cut -d'!' -f2)
    [ -n "$_SEL" ] && [ -b "$_SEL" ] && TARGET_DISK="$_SEL"
fi

echo "Target selezionato: $TARGET_DISK"
[ -b "$TARGET_DISK" ] || { echo "ERROR: disco non valido: $TARGET_DISK"; exit 1; }

EFI_MODE=0; [ -d /sys/firmware/efi ] && EFI_MODE=1
echo "EFI mode: $EFI_MODE"
echo "Device: $(ls -la "$TARGET_DISK" 2>/dev/null)"

# Rilascia il disco da udisks/automount se bloccato.
# Su openSUSE live, udisks2 può montare/bloccare il disco target.
udisksctl unmount -b "$TARGET_DISK" 2>/dev/null || true
udisksctl power-off -b "$TARGET_DISK" 2>/dev/null || true
udevadm settle 2>/dev/null || true
# Smonta tutte le partizioni del disco (per sicurezza)
for _part in $(lsblk -nlo PATH "$TARGET_DISK" 2>/dev/null | tail -n +2); do
    umount -l "$_part" 2>/dev/null || true
done

# Helper parted con elevazione automatica: root → diretto, utente → sudo/pkexec
_parted() {
    if [ "$(id -u)" -eq 0 ]; then
        parted "$@"
    else
        echo "WARN: non root (uid=$(id -u)), provo sudo parted..."
        sudo parted "$@" 2>/dev/null || pkexec parted "$@"
    fi
}

part() { echo "$1" | grep -qE 'nvme|mmcblk' && echo "${1}p${2}" || echo "${1}${2}"; }

wipefs -a "$TARGET_DISK" 2>/dev/null || true
sleep 1

if [ "$EFI_MODE" -eq 1 ]; then
    _parted -s "$TARGET_DISK" mklabel gpt                          || exit 1
    _parted -s "$TARGET_DISK" mkpart ESP  fat32   1MiB   301MiB   || exit 1
    _parted -s "$TARGET_DISK" set 1 esp on
    _parted -s "$TARGET_DISK" mkpart boot ext4  301MiB  1325MiB   || exit 1
    _parted -s "$TARGET_DISK" mkpart root ext4 1325MiB   100%     || exit 1

    PART_EFI=$(part  "$TARGET_DISK" 1)
    PART_BOOT=$(part "$TARGET_DISK" 2)
    PART_ROOT=$(part "$TARGET_DISK" 3)

    partprobe "$TARGET_DISK" 2>/dev/null; sleep 2

    mkfs.vfat -F32 -n EFI  "$PART_EFI"  || exit 1
    mkfs.ext4 -F   -L boot "$PART_BOOT" || exit 1
    mkfs.btrfs -f  -L root "$PART_ROOT" || exit 1

    UUID_EFI=$(blkid  -s UUID -o value "$PART_EFI")
    UUID_BOOT=$(blkid -s UUID -o value "$PART_BOOT")
    UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT")

    # Crea subvolumi btrfs layout openSUSE TW standard:
    # @, @/var, @/usr/local, @/srv, @/root, @/opt, @/home, @/.snapshots
    _BTRFS_TMP=$(mktemp -d /tmp/dc-btrfs-XXXXXX)
    mount "$PART_ROOT" "$_BTRFS_TMP"                      || exit 1
    btrfs subvolume create "$_BTRFS_TMP/@"                || exit 1
    btrfs subvolume create "$_BTRFS_TMP/@/var"            || true
    mkdir -p "$_BTRFS_TMP/@/usr"
    btrfs subvolume create "$_BTRFS_TMP/@/usr/local"      || true
    btrfs subvolume create "$_BTRFS_TMP/@/srv"            || true
    btrfs subvolume create "$_BTRFS_TMP/@/root"           || true
    btrfs subvolume create "$_BTRFS_TMP/@/opt"            || true
    btrfs subvolume create "$_BTRFS_TMP/@/home"           || true
    btrfs subvolume create "$_BTRFS_TMP/@/.snapshots"     || true
    echo "Subvolumi creati:"
    btrfs subvolume list "$_BTRFS_TMP" 2>/dev/null || true
    umount "$_BTRFS_TMP"; rmdir "$_BTRFS_TMP"

    mkdir -p /tmp/calamares-root
    mount -o subvol=@ "$PART_ROOT" /tmp/calamares-root     || exit 1
    mkdir -p /tmp/calamares-root/boot
    mount "$PART_BOOT" /tmp/calamares-root/boot            || exit 1
    # boot/efi creata DOPO il mount di /boot (altrimenti la dir è sul root
    # partition e viene oscurata dal mount di /boot — risultato: mount point
    # does not exist)
    mkdir -p /tmp/calamares-root/boot/efi
    mount "$PART_EFI"  /tmp/calamares-root/boot/efi        || exit 1

    cat > /tmp/dc-install-info.env << ENVEOF
DC_TARGET_DISK=$TARGET_DISK
DC_PART_EFI=$PART_EFI
DC_PART_BOOT=$PART_BOOT
DC_PART_ROOT=$PART_ROOT
DC_UUID_EFI=$UUID_EFI
DC_UUID_BOOT=$UUID_BOOT
DC_UUID_ROOT=$UUID_ROOT
DC_EFI_MODE=1
ENVEOF

else
    _parted -s "$TARGET_DISK" mklabel msdos                        || exit 1
    _parted -s "$TARGET_DISK" mkpart primary ext4 1MiB   1025MiB  || exit 1
    _parted -s "$TARGET_DISK" set 1 boot on
    _parted -s "$TARGET_DISK" mkpart primary ext4 1025MiB 100%    || exit 1

    PART_BOOT=$(part "$TARGET_DISK" 1)
    PART_ROOT=$(part "$TARGET_DISK" 2)

    partprobe "$TARGET_DISK" 2>/dev/null; sleep 2

    mkfs.ext4  -F -L boot "$PART_BOOT" || exit 1
    mkfs.btrfs -f -L root "$PART_ROOT" || exit 1

    UUID_BOOT=$(blkid -s UUID -o value "$PART_BOOT")
    UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT")

    # Crea subvolumi btrfs layout openSUSE TW standard (BIOS path)
    _BTRFS_TMP=$(mktemp -d /tmp/dc-btrfs-XXXXXX)
    mount "$PART_ROOT" "$_BTRFS_TMP"                      || exit 1
    btrfs subvolume create "$_BTRFS_TMP/@"                || exit 1
    btrfs subvolume create "$_BTRFS_TMP/@/var"            || true
    mkdir -p "$_BTRFS_TMP/@/usr"
    btrfs subvolume create "$_BTRFS_TMP/@/usr/local"      || true
    btrfs subvolume create "$_BTRFS_TMP/@/srv"            || true
    btrfs subvolume create "$_BTRFS_TMP/@/root"           || true
    btrfs subvolume create "$_BTRFS_TMP/@/opt"            || true
    btrfs subvolume create "$_BTRFS_TMP/@/home"           || true
    btrfs subvolume create "$_BTRFS_TMP/@/.snapshots"     || true
    echo "Subvolumi creati:"
    btrfs subvolume list "$_BTRFS_TMP" 2>/dev/null || true
    umount "$_BTRFS_TMP"; rmdir "$_BTRFS_TMP"

    mkdir -p /tmp/calamares-root
    mount -o subvol=@ "$PART_ROOT" /tmp/calamares-root     || exit 1
    mkdir -p /tmp/calamares-root/boot
    mount "$PART_BOOT" /tmp/calamares-root/boot            || exit 1

    cat > /tmp/dc-install-info.env << ENVEOF
DC_TARGET_DISK=$TARGET_DISK
DC_PART_EFI=
DC_PART_BOOT=$PART_BOOT
DC_PART_ROOT=$PART_ROOT
DC_UUID_EFI=
DC_UUID_BOOT=$UUID_BOOT
DC_UUID_ROOT=$UUID_ROOT
DC_EFI_MODE=0
ENVEOF
fi

echo "Mount target:"; mount | grep calamares-root
echo "=== disk-setup OK ==="; exit 0
DISKSETUP

    # ──────────────────────────────────────────────────────────────────────────
    # WRITE-FSTAB: scrive /etc/fstab corretto DOPO unpackfs (che sovrascrive
    # il fstab del live). Legge UUIDs da /tmp/dc-install-info.env.
    # Se dc-install-info.env non esiste (caso partition module usato) → skip.
    # ──────────────────────────────────────────────────────────────────────────
    install -Dm755 /dev/stdin /usr/local/bin/dc-write-fstab.sh << 'WRITEFSTAB'
#!/bin/bash
set +e
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"

echo "=== dc-write-fstab $(date) ==="

# ── Rilevazione TARGET: cerca il VERO mount point Calamares ──────────────────
# REGOLA: usare solo mount point reali (mountpoint -q). Mai directory plain
# create da operazioni precedenti (es. mkdir o rsync verso path non montato).
# Calamares 3.3+ usa /tmp/calamares-root-XXXXXXXX (suffisso univoco per run).
echo "[DC] Scansione mount point Calamares:"
findmnt -n -l -o TARGET,SOURCE,FSTYPE 2>/dev/null | grep -E 'calamares|/tmp/cal' || echo "  (nessuno)"

TARGET=""
# Priorità 1: /tmp/calamares-root se è un VERO mount point
if mountpoint -q /tmp/calamares-root 2>/dev/null; then
    TARGET="/tmp/calamares-root"
fi
# Priorità 2: /tmp/calamares-root-* (Calamares con suffisso univoco)
if [ -z "$TARGET" ]; then
    while IFS= read -r _mp; do
        case "$_mp" in /tmp/calamares-root-*)
            TARGET="$_mp"; break ;;
        esac
    done < <(findmnt -n -l -o TARGET 2>/dev/null)
fi
# Priorità 3: mount point standard alternativi
if [ -z "$TARGET" ]; then
    for _p in /mnt/target /target /mnt; do
        if mountpoint -q "$_p" 2>/dev/null; then TARGET="$_p"; break; fi
    done
fi
if [ -z "$TARGET" ]; then
    echo "ERROR: nessun mount point Calamares trovato — partizioni montate?"
    echo "  findmnt:"; findmnt -n -l -o TARGET,SOURCE,FSTYPE 2>/dev/null || true
    exit 1
fi
echo "[DC] Target mount point: $TARGET"
echo "[DC] Contenuto $TARGET: $(ls "$TARGET/" 2>/dev/null | tr '\n' ' ' || echo '(vuoto)')"

if [ ! -d "$TARGET/etc" ]; then
    echo "[DC] WARN: $TARGET/etc non trovato — tentativo recupero LiveOS..."

    # ── Caso 1: C++ unpackfs ha estratto il container LiveOS ─────────────
    # (squashfs.img → LiveOS/rootfs.img, non il rootfs diretto)
    if [ -f "$TARGET/LiveOS/rootfs.img" ]; then
        echo "[DC] Trovato LiveOS/rootfs.img — estrazione in corso..."
        _LMNT=$(mktemp -d /tmp/dc-liveos-XXXXXX)
        # Prova btrfs subvol=@ (openSUSE TW), poi ext4/altri plain
        mount -o loop,ro,subvol=@ "$TARGET/LiveOS/rootfs.img" "$_LMNT" 2>/dev/null
        if ! mountpoint -q "$_LMNT"; then
            mount -o loop,ro "$TARGET/LiveOS/rootfs.img" "$_LMNT" 2>/dev/null
        fi
        if mountpoint -q "$_LMNT"; then
            _RSYNC_SRC="$_LMNT/"
            [ ! -d "$_LMNT/etc" ] && [ -d "$_LMNT/@" ] && _RSYNC_SRC="$_LMNT/@/"
            echo "[DC] rsync da rootfs.img → $TARGET ..."
            rsync -aAX --delete \
                --exclude='/proc/*' --exclude='/sys/*' \
                --exclude='/dev/*'  --exclude='/run/*' \
                --exclude='/tmp/*'  --exclude='/lost+found' \
                "$_RSYNC_SRC" "$TARGET/" 2>&1
            umount -l "$_LMNT" 2>/dev/null || true
            rmdir "$_LMNT" 2>/dev/null || true
            echo "[DC] Recupero da LiveOS/rootfs.img completato"
        else
            echo "[DC] WARN: impossibile montare rootfs.img"; rmdir "$_LMNT" 2>/dev/null || true
        fi
    fi

    # ── Caso 2: nessun rootfs.img — rsync dal sistema live in esecuzione ──
    # ATTENZIONE: rsync SOLO sul target reale (mountpoint verificato sopra)
    if [ ! -d "$TARGET/etc" ]; then
        echo "[DC] Tentativo rsync dal sistema live (/) → $TARGET (mount point reale) ..."
        rsync -aAX --delete \
            --exclude='/proc/*'  --exclude='/sys/*' \
            --exclude='/dev/*'   --exclude='/run/*' \
            --exclude='/tmp/*'   --exclude='/lost+found' \
            --exclude='/mnt/*'   --exclude='/media/*' \
            "/" "$TARGET/" 2>&1
        echo "[DC] rsync live exit: $?"
    fi

    if [ ! -d "$TARGET/etc" ]; then
        echo "ERROR CRITICO: $TARGET/etc non trovato dopo tutti i tentativi di recupero"
        echo "  Contenuto $TARGET:"; ls -la "$TARGET/" 2>/dev/null
        exit 1
    fi
    echo "[DC] Recupero completato — $TARGET/etc ora presente"
fi

# ── Funzione: UUID per mount point con 4 livelli di fallback ─────────────────
# 1. dc-install-info.env (scritto da mountbridge o disk-setup)
# 2. findmnt + blkid su ${TARGET}${mp}
# 3. /proc/mounts grep + blkid
# 4. lsblk scan su tutti i dischi (per FULL C++ mode dove findmnt può fallire)
_uuid_for_mp() {
    local _mp="$1" _var="$2" _uuid="" _dev=""

    # Fonte 1: env file
    if [ -f /tmp/dc-install-info.env ]; then
        . /tmp/dc-install-info.env 2>/dev/null
        eval "_uuid=\${${_var}:-}"
    fi
    [ -n "$_uuid" ] && { echo "$_uuid"; return; }

    # Normalizza path target (evita doppio / per root)
    local _target_path="$TARGET"
    [ "$_mp" != "/" ] && _target_path="${TARGET}${_mp}"

    # Fonte 2: findmnt
    if mountpoint -q "$_target_path" 2>/dev/null; then
        _dev=$(findmnt -n -o SOURCE "$_target_path" 2>/dev/null | head -1)
        # findmnt può tornare device mapper → risolvi
        [ -n "$_dev" ] && _uuid=$(blkid -s UUID -o value "$_dev" 2>/dev/null)
    fi
    [ -n "$_uuid" ] && { echo "$_uuid"; return; }

    # Fonte 3: /proc/mounts (più grezzo ma affidabile)
    _dev=$(awk -v mp="$_target_path" '$2==mp {print $1}' /proc/mounts 2>/dev/null | tail -1)
    # Prova anche senza trailing slash
    [ -z "$_dev" ] && _dev=$(awk -v mp="${_target_path%/}" '$2==mp {print $1}' /proc/mounts 2>/dev/null | tail -1)
    if [ -n "$_dev" ]; then
        _uuid=$(blkid -s UUID -o value "$_dev" 2>/dev/null)
    fi
    [ -n "$_uuid" ] && { echo "$_uuid"; return; }

    # Fonte 4: lsblk — cerca partizioni con MOUNTPOINT che contiene il target path
    _dev=$(lsblk -nlo PATH,MOUNTPOINT 2>/dev/null | awk -v mp="$_target_path" '$2==mp {print $1}' | head -1)
    [ -z "$_dev" ] && \
        _dev=$(lsblk -nlo PATH,MOUNTPOINT 2>/dev/null | awk -v mp="${_target_path%/}" '$2==mp {print $1}' | head -1)
    if [ -n "$_dev" ]; then
        _uuid=$(blkid -s UUID -o value "$_dev" 2>/dev/null)
    fi

    echo "$_uuid"
}

# Funzione: tipo filesystem
_fstype_for_mp() {
    local _mp="$1" _fs=""
    local _target_path="$TARGET"
    [ "$_mp" != "/" ] && _target_path="${TARGET}${_mp}"
    # findmnt
    _fs=$(findmnt -n -o FSTYPE "$_target_path" 2>/dev/null | head -1)
    # fallback: /proc/mounts
    [ -z "$_fs" ] && _fs=$(awk -v mp="$_target_path" '$2==mp {print $3}' /proc/mounts 2>/dev/null | tail -1)
    [ -z "$_fs" ] && _fs=$(awk -v mp="${_target_path%/}" '$2==mp {print $3}' /proc/mounts 2>/dev/null | tail -1)
    # Default sensati
    case "$_mp" in
        /)         echo "${_fs:-ext4}" ;;
        /boot)     echo "${_fs:-ext4}" ;;
        /boot/efi) echo "${_fs:-vfat}" ;;
        *)         echo "${_fs:-auto}" ;;
    esac
}

echo "[DC] DEBUG mount info:"
echo "  mountpoint -q $TARGET: $(mountpoint -q "$TARGET" 2>&1 && echo YES || echo NO)"
echo "  findmnt $TARGET: $(findmnt -n -o SOURCE "$TARGET" 2>/dev/null || echo FAIL)"
echo "  /proc/mounts entries with calamares-root:"
grep calamares-root /proc/mounts 2>/dev/null || echo "  (nessuna)"
echo "  lsblk MOUNTPOINT:"
lsblk -nlo PATH,MOUNTPOINT,FSTYPE 2>/dev/null | grep -E 'calamares|/tmp/' || echo "  (nessuna)"

DC_UUID_ROOT=$(_uuid_for_mp "/"         "DC_UUID_ROOT")
DC_UUID_BOOT=$(_uuid_for_mp "/boot"     "DC_UUID_BOOT")
# EFI: prova /boot/efi (layout DistroClone disk-setup) poi /efi (erase-disk openSUSE)
DC_UUID_EFI=$(_uuid_for_mp  "/boot/efi" "DC_UUID_EFI")
DC_EFI_MP="/boot/efi"
if [ -z "$DC_UUID_EFI" ]; then
    DC_UUID_EFI=$(_uuid_for_mp "/efi" "DC_UUID_EFI")
    [ -n "$DC_UUID_EFI" ] && DC_EFI_MP="/efi"
fi

echo "[DC] UUID rilevati — root:${DC_UUID_ROOT:-MANCANTE} boot:${DC_UUID_BOOT:-?} efi:${DC_UUID_EFI:-?}"

if [ -z "$DC_UUID_ROOT" ]; then
    echo "ERROR CRITICO: UUID root non trovato con nessun metodo!"
    echo "  Il sistema installato NON avrà un fstab valido."
    echo "  Dati diagnostici salvati in $TARGET/etc/fstab.debug"
    {
        echo "# dc-write-fstab FAILED — $(date)"
        echo "# mount:";    mount 2>/dev/null
        echo "# findmnt:";  findmnt 2>/dev/null
        echo "# lsblk:";    lsblk -f 2>/dev/null
        echo "# /proc/mounts:"; cat /proc/mounts 2>/dev/null
    } > "$TARGET/etc/fstab.debug" 2>/dev/null || true
    # NON exit 0: il fstab DEVE esistere. Scrivi un fstab minimale con LABEL fallback.
    echo "[DC] FALLBACK: scrivo fstab con LABEL=root (dracut tenterà label match)"
    _FB_FS_ROOT=$(findmnt -n -o FSTYPE "$TARGET" 2>/dev/null | head -1)
    _FB_FS_ROOT="${_FB_FS_ROOT:-ext4}"
    _FB_OPTS_ROOT="defaults,noatime"
    [ "$_FB_FS_ROOT" = "btrfs" ] && _FB_OPTS_ROOT="defaults,noatime,compress=zstd"
    {
        echo "# /etc/fstab — FALLBACK DistroClone (UUID non trovato) $(date)"
        echo "# ATTENZIONE: verificare manualmente UUID partizioni"
        echo "LABEL=root       /          ${_FB_FS_ROOT}  ${_FB_OPTS_ROOT}  0  1"
        echo "LABEL=boot       /boot      ext4  defaults,noatime  0  2"
        echo "LABEL=EFI        ${DC_EFI_MP:-/boot/efi}  vfat  umask=0077  0  2"
        echo "tmpfs            /tmp       tmpfs  defaults          0  0"
    } > "$TARGET/etc/fstab"
    echo "[DC] WARN: fstab fallback scritto — il boot potrebbe richiedere fix manuale"
    cat "$TARGET/etc/fstab"
    exit 0
fi

_FS_ROOT=$(_fstype_for_mp "/")
_FS_BOOT=$(_fstype_for_mp "/boot")

# Opzioni mount btrfs-aware: aggiungi subvol=@ SOLO se il subvolume @ esiste.
# Calamares erase-disk senza btrfsSubvolumes crea btrfs plain (nessun @) →
# fstab con subvol=@ fa fallire il boot. Con btrfsSubvolumes (Calamares 3.3+)
# il subvolume @ viene creato e rsync va dentro @, quindi subvol=@ è corretto.
_OPTS_ROOT="defaults,noatime"
if [ "$_FS_ROOT" = "btrfs" ]; then
    _OPTS_ROOT="defaults,noatime,compress=zstd"
    if btrfs subvolume list "$TARGET" 2>/dev/null | grep -qE '(^|\s)path @$'; then
        _OPTS_ROOT="defaults,noatime,compress=zstd,subvol=@"
        echo "[DC] btrfs: subvolume @ trovato — fstab usa subvol=@"
    else
        echo "[DC] btrfs: nessun subvolume @ — fstab monta top-level btrfs"
    fi
fi

{
    echo "# /etc/fstab — generato da DistroClone $(date)"
    echo "# <device>           <mount>    <type>  <options>          <dump>  <pass>"
    echo "UUID=$DC_UUID_ROOT   /          ${_FS_ROOT}  ${_OPTS_ROOT}  0  1"

    # btrfs: aggiungi entry per ogni subvolume standard openSUSE TW (es. @/home,
    # @/var, @/opt, ecc.). Senza queste voci, i subvolumi non vengono montati al
    # boot → /home appare vuota anche se dc-post-users.sh ha scritto dentro @/home.
    # IMPLEMENTAZIONE: NON usare `cmd | while` (subshell, perde stato). Usa list
    # capturata in variabile + iterazione esplicita su pairs noti. Se il subvolume
    # standard esiste, scrivi la sua entry. Salva l'output raw in /etc/fstab.debug
    # per diagnostica futura.
    if [ "$_FS_ROOT" = "btrfs" ] && [ -n "$DC_UUID_ROOT" ]; then
        _BTRFS_OPTS="defaults,noatime,compress=zstd"
        _SUBVOL_RAW=$(btrfs subvolume list "$TARGET" 2>&1)
        # Lista paths (ultimo campo). Output normale: "ID X gen Y top level Z path P"
        _SUBVOL_PATHS=$(echo "$_SUBVOL_RAW" | awk '/^ID /{print $NF}')
        echo "[DC] btrfs subvolume list output:" >&2
        echo "$_SUBVOL_RAW" | sed 's/^/  /' >&2
        echo "[DC] paths estratti: $(echo "$_SUBVOL_PATHS" | tr '\n' ' ')" >&2

        for _pair in "@/home:/home" "@/var:/var" "@/usr/local:/usr/local" \
                     "@/srv:/srv" "@/opt:/opt" "@/root:/root" "@/.snapshots:/.snapshots"; do
            _sv="${_pair%%:*}"
            _sv_mp="${_pair##*:}"
            if echo "$_SUBVOL_PATHS" | grep -qxF "$_sv"; then
                echo "  [DC] $_sv → $_sv_mp" >&2
                echo "UUID=$DC_UUID_ROOT  $_sv_mp  btrfs  ${_BTRFS_OPTS},subvol=${_sv}  0  0"
            else
                echo "  [DC] subvolume $_sv non trovato — skip" >&2
            fi
        done
    fi

    [ -n "$DC_UUID_BOOT" ] && \
        echo "UUID=$DC_UUID_BOOT  /boot      ${_FS_BOOT}  defaults,noatime  0  2"
    [ -n "$DC_UUID_EFI" ] && \
        echo "UUID=$DC_UUID_EFI  ${DC_EFI_MP}  vfat  umask=0077,defaults  0  2"
    echo "tmpfs               /tmp       tmpfs  defaults              0  0"
} > "$TARGET/etc/fstab"

echo "[DC] fstab scritto:"; cat "$TARGET/etc/fstab"

# Verifica: il fstab DEVE contenere una riga per /
if ! grep -q 'UUID=.*/' "$TARGET/etc/fstab" 2>/dev/null; then
    echo "ERROR: fstab scritto ma non contiene entry root valida!"
    exit 1
fi

echo "=== dc-write-fstab OK ==="; exit 0
WRITEFSTAB

    write_shellprocess_conf /etc/calamares/modules/disk-setup.conf true 300 \
        /usr/local/bin/dc-disk-setup.sh
    write_shellprocess_conf /etc/calamares/modules/write-fstab.conf true 60 \
        /usr/local/bin/dc-write-fstab.sh

    # ──────────────────────────────────────────────────────────────────────────
    # EXTRACT-SQUASHFS: rimpiazza il modulo C++ unpackfs (assente in openSUSE).
    # Usa unsquashfs (squashfs-tools) o mount+rsync come fallback.
    # Il target /tmp/calamares-root è già montato da disk-setup.
    # ──────────────────────────────────────────────────────────────────────────
    install -Dm755 /dev/stdin /usr/local/bin/dc-extract-squashfs.sh << 'EXTRACTSCRIPT'
#!/bin/bash
set +e

export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"
echo "=== dc-extract-squashfs $(date) ==="

TARGET="/tmp/calamares-root"
if [ ! -d "$TARGET" ]; then
    echo "ERROR: $TARGET non esiste — disk-setup eseguito?"; exit 1
fi

# Trova squashfs tramite helper DistroClone
SQUASHFS=""
[ -x /usr/local/bin/distroClone-find-squashfs.sh ] && \
    SQUASHFS=$(/usr/local/bin/distroClone-find-squashfs.sh 2>/dev/null)

# Fallback: cerca in path noti (openSUSE live usa label openSUSE-TUMBLEWEED)
if [ -z "$SQUASHFS" ] || [ ! -e "$SQUASHFS" ]; then
    for _sq in \
        /run/initramfs/live/LiveOS/squashfs.img \
        /run/initramfs/live/live/filesystem.squashfs \
        /run/live/medium/LiveOS/squashfs.img \
        /run/live/medium/live/filesystem.squashfs \
        /dev/disk/by-label/openSUSE-TUMBLEWEED \
        /run/initramfs/livedev/LiveOS/squashfs.img; do
        [ -e "$_sq" ] && SQUASHFS="$_sq" && break
    done
fi

if [ -z "$SQUASHFS" ] || [ ! -e "$SQUASHFS" ]; then
    # Ultima risorsa: cerca squashfs montato in /proc/mounts
    SQUASHFS=$(awk '/squashfs|LiveOS/ {print $1}' /proc/mounts 2>/dev/null | \
               grep -E '\.img$|\.squashfs$' | head -1)
fi

echo "Squashfs: ${SQUASHFS:-NON TROVATO}"
echo "Target  : $TARGET"

if [ -z "$SQUASHFS" ] || [ ! -e "$SQUASHFS" ]; then
    echo "ERROR: squashfs non trovato"; exit 1
fi

# Estrazione con unsquashfs (preferito) o mount+rsync (fallback)
# Post-estrazione: pulisci artefatti host dal target
_dc_post_extract_cleanup() {
    local _t="$1"
    # Rimuovi /etc/localtime: il modulo locale C++ di Calamares
    # crea il symlink → /usr/share/zoneinfo/... e fallisce se il file esiste già
    rm -f "$_t/etc/localtime"
    echo "[DC] Rimosso /etc/localtime dal target (verrà ricreato da Calamares locale module)"

    # ── Snapper cleanup: rimuovi snapshot host MA mantieni configurazione ────
    # Lo squashfs contiene snapshot del host (inutili nel clone).
    # Puliamo i DATI degli snapshot vecchi ma manteniamo:
    #   - /etc/snapper/configs/root (config snapper)
    #   - SNAPPER_CONFIGS="root" in sysconfig (abilita snapper)
    #   - grub.d snapshot scripts (generano voci solo se ci sono snapshot)
    # Così snapper funziona out-of-the-box al primo boot.
    rm -rf "$_t/.snapshots"/[0-9]* 2>/dev/null || true
    rm -rf "$_t/var/lib/snapper/snapshots"/* 2>/dev/null || true
    echo "[DC] ✓ Snapper: snapshot host rimossi, config mantenuta"
}

_dc_liveos_fallback() {
    # openSUSE/Fedora LiveOS format: squashfs contiene LiveOS/rootfs.img
    # (immagine btrfs/ext4 del filesystem reale). Monta rootfs.img e rsync.
    # Per btrfs: prova prima subvol=@ (layout openSUSE TW), poi mount plain.
    # Se il mount plain mostra il top-level btrfs (con @ come subdir invece di
    # root), usa "$_rmnt/@/" come sorgente per rsync.
    local _rootfs="$TARGET/LiveOS/rootfs.img"
    if [ ! -f "$_rootfs" ]; then
        echo "[DC] LiveOS fallback: $TARGET/LiveOS/rootfs.img non trovato"; return 1
    fi
    echo "[DC] LiveOS container rilevato — estrazione da rootfs.img..."
    local _rmnt _rsync_src
    _rmnt=$(mktemp -d /tmp/dc-liveos-XXXXXX)
    # Primo tentativo: btrfs subvol=@ (openSUSE TW default)
    mount -o loop,ro,subvol=@ "$_rootfs" "$_rmnt" 2>/dev/null
    if mountpoint -q "$_rmnt"; then
        echo "[DC] Montato rootfs.img con subvol=@ (btrfs openSUSE)"
        _rsync_src="$_rmnt/"
    else
        # Secondo tentativo: mount generico (ext4 o btrfs senza subvolumi espliciti)
        mount -o loop,ro "$_rootfs" "$_rmnt" 2>/dev/null
        if ! mountpoint -q "$_rmnt"; then
            echo "ERROR: impossibile montare $TARGET/LiveOS/rootfs.img"; rmdir "$_rmnt"; return 1
        fi
        if [ ! -d "$_rmnt/etc" ] && [ -d "$_rmnt/@" ]; then
            # Top-level btrfs montato: il rootfs reale è nella subdir "@"
            echo "[DC] Top-level btrfs rilevato — uso @/ come sorgente rsync"
            _rsync_src="$_rmnt/@/"
        else
            _rsync_src="$_rmnt/"
        fi
    fi
    rsync -aAX --delete \
        --exclude='/proc/*' --exclude='/sys/*' \
        --exclude='/dev/*'  --exclude='/run/*' \
        --exclude='/tmp/*'  --exclude='/lost+found' \
        "$_rsync_src" "$TARGET/" 2>&1
    local _rsync_rc=$?
    umount -l "$_rmnt" 2>/dev/null || true
    rmdir  "$_rmnt"  2>/dev/null || true
    echo "[DC] LiveOS rsync exit: $_rsync_rc"
    return $_rsync_rc
}

if command -v unsquashfs >/dev/null 2>&1; then
    echo "Usando unsquashfs..."
    # -f: force sovrascrittura; -d: destinazione; -no-xattrs: evita exit 2 su fs senza xattr support
    unsquashfs -f -no-xattrs -d "$TARGET" "$SQUASHFS" 2>&1
    _rc=$?
    echo "[DC] unsquashfs exit: $_rc"
    if [ $_rc -eq 0 ] && [ ! -d "$TARGET/etc" ]; then
        # LiveOS container: unsquashfs ha estratto LiveOS/rootfs.img, non il rootfs diretto
        echo "[DC] Target privo di /etc dopo unsquashfs — probabile LiveOS container (openSUSE/Fedora)"
        _dc_liveos_fallback
        _rc=$?
    fi
    [ $_rc -eq 0 ] && _dc_post_extract_cleanup "$TARGET"
    exit $_rc
else
    echo "unsquashfs non disponibile, uso mount+rsync..."
    _SQMNT=$(mktemp -d /tmp/dc-sq-XXXXXX)
    mount -o loop,ro "$SQUASHFS" "$_SQMNT" 2>/dev/null || \
    mount -o ro "$SQUASHFS" "$_SQMNT" 2>/dev/null
    if ! mountpoint -q "$_SQMNT"; then
        echo "ERROR: impossibile montare squashfs"; rmdir "$_SQMNT"; exit 1
    fi
    # Rileva se il mount contiene un LiveOS container (squashfs.img come contenitore)
    if [ ! -d "$_SQMNT/etc" ] && [ -f "$_SQMNT/LiveOS/rootfs.img" ]; then
        echo "[DC] LiveOS container nel squashfs montato — estrazione da rootfs.img..."
        _lrmnt=$(mktemp -d /tmp/dc-liveos-XXXXXX)
        mount -o loop,ro "$_SQMNT/LiveOS/rootfs.img" "$_lrmnt" 2>/dev/null
        if ! mountpoint -q "$_lrmnt"; then
            echo "ERROR: impossibile montare rootfs.img"; rmdir "$_lrmnt"
            umount -l "$_SQMNT" 2>/dev/null || true; rmdir "$_SQMNT" 2>/dev/null || true
            exit 1
        fi
        rsync -aAX --delete \
            --exclude='/proc/*' --exclude='/sys/*' \
            --exclude='/dev/*'  --exclude='/run/*' \
            --exclude='/tmp/*'  --exclude='/lost+found' \
            "$_lrmnt/" "$TARGET/" 2>&1
        _rc=$?
        umount -l "$_lrmnt" 2>/dev/null || true
        rmdir  "$_lrmnt"  2>/dev/null || true
    else
        rsync -aAX --delete \
            --exclude='/proc/*' --exclude='/sys/*' \
            --exclude='/dev/*'  --exclude='/run/*' \
            --exclude='/tmp/*'  --exclude='/lost+found' \
            "$_SQMNT/" "$TARGET/" 2>&1
        _rc=$?
    fi
    umount -l "$_SQMNT" 2>/dev/null || true
    rmdir  "$_SQMNT" 2>/dev/null || true
    echo "[DC] rsync exit: $_rc"
    [ $_rc -eq 0 ] && _dc_post_extract_cleanup "$TARGET"
    exit $_rc
fi
EXTRACTSCRIPT

    write_shellprocess_conf /etc/calamares/modules/extract-squashfs.conf true 1800 \
        /usr/local/bin/dc-extract-squashfs.sh

    echo "[DC] ✓ extract-squashfs configurato (rimpiazza modulo unpackfs C++ su openSUSE)"

    # ──────────────────────────────────────────────────────────────────────────
    # WRITE-MACHINE-ID: rimpiazza il modulo C++ machineid che fallisce perché
    # GlobalStorage.rootMountPoint non è popolato (bypassed il modulo C++ mount).
    # Genera un UUID casuale e lo scrive in /etc/machine-id nel target.
    # ──────────────────────────────────────────────────────────────────────────
    install -Dm755 /dev/stdin /usr/local/bin/dc-write-machine-id.sh << 'MACHINEID'
#!/bin/bash
set +e
export PATH="/usr/sbin:/sbin:/usr/local/sbin:/usr/bin:/bin:/usr/local/bin:$PATH"

TARGET="/tmp/calamares-root"
echo "=== dc-write-machine-id $(date) ==="

if [ ! -d "$TARGET/etc" ]; then
    echo "ERROR: $TARGET/etc non trovato — extract-squashfs eseguito?"; exit 1
fi

# Genera UUID senza trattini (formato machine-id)
if command -v uuidgen >/dev/null 2>&1; then
    MACHINE_ID=$(uuidgen | tr -d '-')
elif [ -r /proc/sys/kernel/random/uuid ]; then
    MACHINE_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
else
    MACHINE_ID=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 32)
fi

printf '%s\n' "$MACHINE_ID" > "$TARGET/etc/machine-id"
chmod 444 "$TARGET/etc/machine-id"
echo "[DC] machine-id: $MACHINE_ID"

# dbus machine-id: symlink standard verso /etc/machine-id
mkdir -p "$TARGET/var/lib/dbus"
if [ ! -e "$TARGET/var/lib/dbus/machine-id" ]; then
    ln -sf /etc/machine-id "$TARGET/var/lib/dbus/machine-id" 2>/dev/null || \
        cp "$TARGET/etc/machine-id" "$TARGET/var/lib/dbus/machine-id"
fi

echo "=== dc-write-machine-id OK ==="; exit 0
MACHINEID

    write_shellprocess_conf /etc/calamares/modules/write-machine-id.conf true 30 \
        /usr/local/bin/dc-write-machine-id.sh

    echo "[DC] ✓ write-machine-id configurato (rimpiazza modulo machineid C++ su openSUSE)"

    # ──────────────────────────────────────────────────────────────────────────
    # SETROOTMOUNT: modulo Python che imposta rootMountPoint in GlobalStorage.
    # PROBLEMA: Calamares 3.2.62 NON legge "globalStorage:" da settings.yaml
    #   (Settings.cpp non ha questo parser — introdotto solo in 3.3.x).
    #   Senza rootMountPoint tutti i moduli C++ (locale, keyboard, users, ecc.)
    #   operano sul filesystem HOST invece che sul target installato.
    # SOLUZIONE: modulo Python eseguito come PRIMO passo nell'exec sequence.
    #   Il build openSUSE compila Python3 + Boost.Python (verificato nel .spec).
    # NOTA: il module.desc va in $CAL_MODULES (dove Calamares cerca i moduli),
    #   NON in /etc/calamares/modules/ (solo per file .conf di configurazione).
    # ──────────────────────────────────────────────────────────────────────────
    mkdir -p "${CAL_MODULES}/setrootmount"

    cat > "${CAL_MODULES}/setrootmount/module.desc" << 'MODESC'
---
type: "job"
name: "setrootmount"
interface: "python"
script: "main.py"
noconfig: true
MODESC

    cat > "${CAL_MODULES}/setrootmount/main.py" << 'MAINPY'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Calamares Python module: imposta rootMountPoint in GlobalStorage.
# Necessario per openSUSE: il modulo C++ "mount" non è compilato nel
# pacchetto Calamares openSUSE (usa YaST nativo → Calamares minimale).
# Tutti i moduli C++ successivi (locale, keyboard, users, displaymanager,
# networkcfg, ecc.) leggono rootMountPoint per accedere al target.

import libcalamares

ROOT_MOUNT_POINT = "/tmp/calamares-root"

def pretty_name():
    return "Imposta mount point installazione"

def run():
    libcalamares.globalstorage.insert("rootMountPoint", ROOT_MOUNT_POINT)
    libcalamares.utils.debug("[DC] rootMountPoint impostato a " + ROOT_MOUNT_POINT)
    return None
MAINPY

    echo "[DC] ✓ setrootmount Python module creato (${CAL_MODULES}/setrootmount/)"

    # ──────────────────────────────────────────────────────────────────────────
    # MOUNTBRIDGE: modulo Python per la modalità HYBRID.
    # Quando il modulo partition C++ è disponibile (UI erase/manual/encrypt)
    # ma mount/unpackfs C++ mancano, mountbridge fa da ponte:
    #   1. Legge GlobalStorage.partitions (scritto dal partition C++ exec)
    #   2. Monta le partizioni nell'ordine corretto (/ → /boot → /boot/efi)
    #   3. Monta VFS extras (proc, sys, dev, etc.) per i moduli chroot
    #   4. Imposta rootMountPoint in GlobalStorage
    #   5. Scrive /tmp/dc-install-info.env per dc-write-fstab.sh
    # ──────────────────────────────────────────────────────────────────────────
    mkdir -p "${CAL_MODULES}/mountbridge"

    cat > "${CAL_MODULES}/mountbridge/module.desc" << 'MBDESC'
---
type: "job"
name: "mountbridge"
interface: "python"
script: "main.py"
noconfig: true
MBDESC

    cat > "${CAL_MODULES}/mountbridge/main.py" << 'MBPY'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Calamares Python module: mountbridge
# Ponte tra il modulo partition C++ (che crea/formatta le partizioni e scrive
# le info in GlobalStorage) e i moduli successivi che operano nel chroot.
# Usato nella modalita' HYBRID quando mount/unpackfs C++ non sono disponibili.

import libcalamares
import subprocess
import os

ROOT_MOUNT_POINT = "/tmp/calamares-root"


def pretty_name():
    return "Mounting partitions (DistroClone bridge)"


def _mount(device, target, fstype=None, options=None):
    """Mount helper con logging."""
    cmd = ["mount"]
    if fstype:
        cmd += ["-t", fstype]
    if options:
        cmd += ["-o", options]
    cmd += [device, target]
    libcalamares.utils.debug("[DC] mount: {} -> {}".format(device, target))
    ret = subprocess.run(cmd, capture_output=True, text=True)
    if ret.returncode != 0:
        libcalamares.utils.warning("[DC] mount failed: " + ret.stderr.strip())
        return False
    return True


def _get_uuid(device):
    """Ottieni UUID di un device via blkid."""
    try:
        ret = subprocess.run(
            ["blkid", "-s", "UUID", "-o", "value", device],
            capture_output=True, text=True, timeout=10
        )
        return ret.stdout.strip()
    except Exception:
        return ""


def run():
    gs = libcalamares.globalstorage

    # Leggi partizioni da GlobalStorage (scritte dal partition C++ exec)
    partitions = gs.value("partitions")
    if not partitions:
        libcalamares.utils.warning("[DC] mountbridge: nessuna partizione in GlobalStorage")
        return ("Mount failed", "Il modulo partition non ha creato partizioni in GlobalStorage.")

    libcalamares.utils.debug(
        "[DC] mountbridge: {} partizioni trovate".format(len(partitions))
    )

    # Imposta rootMountPoint
    gs.insert("rootMountPoint", ROOT_MOUNT_POINT)
    os.makedirs(ROOT_MOUNT_POINT, exist_ok=True)

    # Ordina per profondita' mount point: / prima, poi /boot, poi /boot/efi
    def _depth(p):
        mp = p.get("mountPoint") or ""
        if not mp or mp == "none":
            return 999
        return mp.rstrip("/").count("/")

    sorted_parts = sorted(partitions, key=_depth)

    env_data = {}
    efi_mode = 0

    for part in sorted_parts:
        mp = part.get("mountPoint") or ""
        device = part.get("device") or ""
        fs = part.get("fs") or ""

        if not mp or mp == "none" or not device:
            continue

        target = ROOT_MOUNT_POINT + mp
        os.makedirs(target, exist_ok=True)

        # Monta (btrfs root: usa subvol=@ per layout openSUSE TW)
        mount_opts = None
        if mp == "/" and fs == "btrfs":
            mount_opts = "subvol=@"
        if not _mount(device, target, options=mount_opts):
            return (
                "Mount failed",
                "Impossibile montare {} su {}.".format(device, target)
            )

        # Recupera UUID (preferisci GlobalStorage, fallback blkid)
        uuid = part.get("uuid") or part.get("UUID") or _get_uuid(device)

        # Traccia per env file (usato da dc-write-fstab.sh)
        if mp == "/":
            env_data["DC_UUID_ROOT"] = uuid
        elif mp == "/boot":
            env_data["DC_UUID_BOOT"] = uuid
        elif mp in ("/boot/efi", "/efi"):
            env_data["DC_UUID_EFI"] = uuid
            efi_mode = 1

        libcalamares.utils.debug(
            "[DC] ✓ {} montato su {} (UUID={})".format(device, target, uuid)
        )

    # ── VFS extras: proc, sys, dev, run (necessari per chroot) ────────────
    vfs_mounts = [
        ("proc",    "proc",   os.path.join(ROOT_MOUNT_POINT, "proc"),    None),
        ("sysfs",   "sysfs",  os.path.join(ROOT_MOUNT_POINT, "sys"),     None),
        ("/dev",    None,      os.path.join(ROOT_MOUNT_POINT, "dev"),     "bind"),
        ("/dev/pts", None,     os.path.join(ROOT_MOUNT_POINT, "dev/pts"), "bind"),
        ("tmpfs",   "tmpfs",  os.path.join(ROOT_MOUNT_POINT, "run"),     None),
        ("/run/udev", None,    os.path.join(ROOT_MOUNT_POINT, "run/udev"), "bind"),
    ]
    for src, fstype, tgt, opts in vfs_mounts:
        os.makedirs(tgt, exist_ok=True)
        if opts == "bind":
            _mount(src, tgt, options="bind")
        elif fstype:
            _mount(src, tgt, fstype=fstype)

    # EFI vars (se disponibile)
    if os.path.isdir("/sys/firmware/efi"):
        efi_vars = os.path.join(ROOT_MOUNT_POINT, "sys/firmware/efi/efivars")
        os.makedirs(efi_vars, exist_ok=True)
        _mount("efivarfs", efi_vars, fstype="efivarfs")

    # ── Scrivi env file per dc-write-fstab.sh ─────────────────────────────
    with open("/tmp/dc-install-info.env", "w") as f:
        for k, v in env_data.items():
            f.write("{}={}\n".format(k, v))
        f.write("DC_EFI_MODE={}\n".format(efi_mode))

    libcalamares.utils.debug(
        "[DC] mountbridge completato: rootMountPoint=" + ROOT_MOUNT_POINT
    )
    return None
MBPY

    echo "[DC] ✓ mountbridge Python module creato (${CAL_MODULES}/mountbridge/)"
}

dc_settings_conf() {
    HAS_LOCALECFG=0
    if [ -f "${CAL_MODULES}/localecfg/module.desc" ] || \
       [ -f "/usr/lib/calamares/modules/localecfg/module.desc" ] || \
       [ -f "/usr/lib64/calamares/modules/localecfg/module.desc" ]; then
        HAS_LOCALECFG=1
    fi

    # Fix 33: detect services-systemd C++ module per Fedora/openSUSE
    HAS_SERVICES_SYSTEMD=0
    for _d in "${CAL_MODULES}/services-systemd" \
              "/usr/lib/calamares/modules/services-systemd" \
              "/usr/lib64/calamares/modules/services-systemd"; do
        if ls "$_d"/*.so >/dev/null 2>&1; then
            HAS_SERVICES_SYSTEMD=1; break
        fi
    done
    echo "  services-systemd module: ${HAS_SERVICES_SYSTEMD} (Fix 33)"

    settings_begin

    settings_add_instance "dc-btrfs-setup"     "dc-btrfs-setup.conf"
    settings_add_instance "dc-post-users"      "dc-post-users.conf"
    settings_add_instance "cleanup-live-conf"  "cleanup-live-conf.conf"
    settings_add_instance "rebuild-initramfs"  "rebuild-initramfs.conf"
    settings_add_instance "disk-setup"         "disk-setup.conf"
    settings_add_instance "write-fstab"        "write-fstab.conf"
    settings_add_instance "extract-squashfs"   "extract-squashfs.conf"
    settings_add_instance "write-machine-id"   "write-machine-id.conf"
    settings_add_instance "dc-final-fixes"     "dc-final-fixes.conf"

    settings_begin_sequence

    if [ "$HAS_LOCALECFG" -eq 1 ]; then
        settings_exec_add "localecfg"
    fi

    settings_exec_add "users"
    settings_exec_add "shellprocess@dc-post-users"
    settings_exec_add "displaymanager"
    settings_exec_add "networkcfg"
    settings_exec_add "hwclock"

    settings_exec_add "shellprocess@cleanup-live-conf"

    # Assicura fstab corretto su TUTTI i path (full C++, hybrid, shellprocess).
    # dc-write-fstab.sh usa findmnt+blkid come fonte primaria (non solo env file)
    # → sovrascrive il fstab del live squashfs con gli UUID delle nuove partizioni.
    # Su HYBRID/SHELLPROCESS è già nel settings_begin_sequence; qui è il run garantito.
    settings_exec_add "shellprocess@write-fstab"

    # Fix 33: usa services-systemd solo se il modulo C++ è disponibile
    if [ "$HAS_SERVICES_SYSTEMD" -eq 1 ]; then
        settings_exec_add "services-systemd"
    fi

    # Ricostruisci initramfs nel target (rimuove hook live dmsquash; obbligatorio
    # altrimenti il sistema installato si blocca su "dracut initqueue hook")
    settings_exec_add "shellprocess@rebuild-initramfs"

    settings_exec_add "shellprocess@grubinstall"
    settings_exec_add "shellprocess@dc-final-fixes"
    settings_exec_add "umount"

    settings_finish
}
