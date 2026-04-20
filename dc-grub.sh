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

    # Bootloader ID dal distro
    local distro_id bootloader_id
    distro_id=$(. /etc/os-release 2>/dev/null; echo "${ID:-linux}")
    bootloader_id=$(printf '%s' "$distro_id" | sed 's/./\u&/')

    echo "[DC] grub-install: mode=$boot_mode cmd=$grub_cmd bootloader-id=$bootloader_id"

    if [ "$boot_mode" = "uefi" ]; then
        _dc_grub_uefi "$grub_cmd" "$bootloader_id"
    else
        _dc_grub_bios "$grub_cmd"
    fi

    # ── Fedora/openSUSE: garantisce BLS entries prima di grub2-mkconfig ─────────
    # grub2-mkconfig con BLS richiede entries in /boot/loader/entries/ per
    # generare voci kernel. Se vuota → GRUB mostra solo "UEFI Firmware Settings".
    # dracut non crea BLS entries; serve kernel-install.
    if command -v grub2-install >/dev/null 2>&1; then
        local _bls_dir="/boot/loader/entries"
        mkdir -p "$_bls_dir"
        local _bls_count
        _bls_count=$(ls "${_bls_dir}"/*.conf 2>/dev/null | wc -l)
        echo "[DC] BLS entries trovate: $_bls_count in $_bls_dir"
        if [ "$_bls_count" -eq 0 ]; then
            echo "[DC] BLS entries mancanti — ricreo con kernel-install..."
            local _kver
            _kver=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)
            if [ -n "$_kver" ]; then
                echo "[DC] kernel-install add $_kver /boot/vmlinuz-$_kver"
                kernel-install add "$_kver" "/boot/vmlinuz-${_kver}" 2>&1 || {
                    # Fallback: crea BLS entry manuale
                    echo "[DC] kernel-install fallito — creo BLS entry manuale"
                    local _root_uuid
                    _root_uuid=$(awk '$2=="/" {print $1}' /etc/fstab 2>/dev/null | \
                        sed 's|UUID=||')
                    local _title
                    _title=$(. /etc/os-release 2>/dev/null; \
                        echo "${PRETTY_NAME:-Linux} (${_kver})")
                    # Legge GRUB_CMDLINE_LINUX (rootflags, rd.luks.uuid, etc.)
                    local _bls_extra=""
                    _bls_extra=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub 2>/dev/null | \
                        sed -e 's/^GRUB_CMDLINE_LINUX=//' -e 's/^"//' -e 's/"$//' \
                            -e "s/^'//" -e "s/'$//")
                    cat > "${_bls_dir}/${distro_id}-${_kver}.conf" << BLSEOF
title ${_title}
version ${_kver}
linux /vmlinuz-${_kver}
initrd /initramfs-${_kver}.img
options root=UUID=${_root_uuid} ro loglevel=3 quiet${_bls_extra:+ ${_bls_extra}}
id ${distro_id}-${_kver}
grub_users \$grub_users
grub_arg --unrestricted
grub_class kernel
BLSEOF
                    echo "[DC] ✓ BLS entry creata: ${distro_id}-${_kver}.conf"
                }
            else
                echo "[DC] WARN: nessun kernel in /lib/modules — BLS entries non create"
            fi
        fi
        echo "[DC] BLS entries dopo fix: $(ls "${_bls_dir}"/*.conf 2>/dev/null | wc -l)"
    fi

    # ── Snapper cleanup before grub-mkconfig ────────────────────────────────
    # /.snapshots contains HOST btrfs snapshots inherited via rsync — always
    # purge them (they'd appear as phantom entries in the clone's GRUB menu).
    # Snapper config + openSUSE snapper-grub-plugin scripts are treated
    # differently per family:
    #   - openSUSE: destroy config (rebuilt at firstboot via dc-firstboot)
    #   - Arch (CachyOS): preserve config — grub-btrfs reads @snapshots
    #     natively and dc-firstboot runs `snapper create-config` only if missing.
    local _snapper_grub_disabled=0
    if [ "${DC_FAMILY:-${DC_DISTRO:-}}" = "opensuse" ]; then
        for _sg in /etc/grub.d/80_suse_btrfs_snapshot \
                   /etc/grub.d/81_suse_btrfs_snapshot; do
            if [ -x "$_sg" ]; then
                chmod -x "$_sg"
                echo "[DC] ✓ Disabilitato $_sg (snapper-grub-plugin)"
                _snapper_grub_disabled=1
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

    # Always: purge host snapper metadata in /var/lib/snapper/snapshots
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

    # grub-mkconfig
    echo "[DC] Generazione $grub_cfg ..."
    if "$grub_cfg_cmd" -o "$grub_cfg" 2>&1; then
        echo "[DC] ✓ $grub_cfg generato"
    else
        echo "[DC] ERROR: $grub_cfg_cmd fallito"
        return 1
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
        echo "[DC] DEBUG DISK=${DISK:-non definito}"
        echo "[DC] DEBUG fstab EFI: $(grep '/boot/efi' /etc/fstab 2>/dev/null | head -1 || echo 'assente')"
        [ -n "${DISK:-}" ] && \
            echo "[DC] DEBUG lsblk /dev/${DISK}: $(lsblk -lno NAME,PARTTYPE,FSTYPE "/dev/${DISK}" 2>/dev/null | tr '\n' '|')"

        # Tentativo 1: mount da fstab
        if grep -q '[[:space:]]/boot/efi[[:space:]]' /etc/fstab 2>/dev/null; then
            mkdir -p /boot/efi
            mount /boot/efi 2>/dev/null \
                && echo "[DC] ✓ /boot/efi montato da fstab" \
                || echo "[DC] WARN: mount da fstab fallito"
        else
            echo "[DC] DEBUG: /boot/efi assente da fstab — salto tentativo 1"
        fi

        # Tentativo 2: lsblk su DISK (già noto da dc-crypto.sh)
        if ! grep -q '/boot/efi' /proc/mounts 2>/dev/null && [ -n "${DISK:-}" ]; then
            local _esp_dev=""
            _esp_dev=$(lsblk -lno NAME,PARTTYPE "/dev/${DISK}" 2>/dev/null \
                       | awk '/c12a7328-f81f-11d2-ba4b-00a0c93ec93b/ {print "/dev/"$1}' \
                       | head -1)
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

        # Tentativo 3: blkid globale PARTTYPE EFI
        if ! grep -q '/boot/efi' /proc/mounts 2>/dev/null; then
            local _esp_global=""
            _esp_global=$(blkid -t PARTTYPE='c12a7328-f81f-11d2-ba4b-00a0c93ec93b' \
                          -o device 2>/dev/null | head -1)
            if [ -n "$_esp_global" ]; then
                mkdir -p /boot/efi
                mount "$_esp_global" /boot/efi 2>/dev/null \
                    && echo "[DC] ✓ /boot/efi montato da $_esp_global (blkid globale)" \
                    || echo "[DC] WARN: mount $_esp_global fallito"
            else
                echo "[DC] WARN: blkid non trova partizioni PARTTYPE=EFI"
            fi
        fi

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

    # Modalità grafica: necessaria per il tema grafico della distro
    sed -i '/^GRUB_GFXMODE=/d; /^GRUB_GFXPAYLOAD_LINUX=/d' \
        /etc/default/grub 2>/dev/null || true
    echo 'GRUB_GFXMODE="1024x768,auto"' >> /etc/default/grub
    echo 'GRUB_GFXPAYLOAD_LINUX="keep"' >> /etc/default/grub

    # Colori fallback testo (attivi solo se GRUB_THEME non è impostato)
    sed -i '/^GRUB_COLOR_NORMAL=/d; /^GRUB_COLOR_HIGHLIGHT=/d' \
        /etc/default/grub 2>/dev/null || true
    echo 'GRUB_COLOR_NORMAL="light-gray/black"' >> /etc/default/grub
    echo 'GRUB_COLOR_HIGHLIGHT="white/dark-gray"' >> /etc/default/grub

    # GRUB_THEME e GRUB_BACKGROUND: lasciati intatti — il clone eredita
    # il tema grafico originale della distro sorgente (Garuda, CachyOS,
    # EndeavourOS, Manjaro, openSUSE ecc.) così com'è nel rootfs clonato.
    echo "[DC] ✓ GRUB visual configurato — tema originale distro preservato (${_distro_pretty})"
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
