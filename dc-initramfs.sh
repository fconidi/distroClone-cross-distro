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
