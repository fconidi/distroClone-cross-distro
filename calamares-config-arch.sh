#!/bin/bash
# =============================================================================
# calamares-config-arch.sh — Modulo famiglia Arch/CachyOS/Garuda/EndeavourOS/Manjaro
# =============================================================================
# Sourced da calamares-config.sh (orchestratore).
# Definisce le funzioni: dc_set_paths, dc_users_conf, dc_remove_live_user,
#                        dc_configure_family, dc_settings_conf
# =============================================================================

dc_set_paths() {
    CAL_MODULES="/usr/lib/calamares/modules"
    PKG_BACKEND="pacman"
    GRUB_CMD="grub-install"
    GRUB_CFG_CMD="grub-mkconfig -o /boot/grub/grub.cfg"
    _ARCH_MACHINE=$(uname -m)
    SQUASHFS_PATH="/run/archiso/bootmnt/arch/${_ARCH_MACHINE}/airootfs.sfs"
}

dc_users_conf() {
    cat > /etc/calamares/modules/users.conf << 'USERS_ARCH'
---
defaultGroups:
  - name: users
    mustexist: false
  - name: audio
    mustexist: false
  - name: video
    mustexist: false
  - name: wheel
    mustexist: true
  - name: storage
    mustexist: false
  - name: optical
    mustexist: false
  - name: network
    mustexist: false
  - name: power
    mustexist: false
  - name: bluetooth
    mustexist: false
  - name: sudo
    mustexist: false

autologinGroup: autologin
doAutologin: false
sudoersGroup: wheel
# setRootPassword: true + doReusePassword: true → root prende la stessa password utente.
# CachyOS/Garuda Calamares a volte non mostra il secondo campo password (o lo nasconde
# via theme QML), lasciando root locked se doReusePassword=false. Con reuse=true
# il problema è risolto a monte: una sola password, applicata a entrambi.
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
USERS_ARCH

    # ── services-systemd.conf: disabilita servizi live CachyOS/Arch ────────
    # CRITICO: senza questo, il modulo services-systemd di Calamares potrebbe
    # RE-ABILITARE i servizi live (cachyos-configure-after-reboot, archiso-*, ecc.)
    # che al primo boot rimuovono aggressivamente /home e utenti.
    # Questi servizi sono nel squashfs (già disabled nel CHROOT_ARCH_EOF),
    # ma services-systemd li ri-abiliterebbe se non esplicitamente elencati qui.
    cat > /etc/calamares/modules/services-systemd.conf << 'SVCSYSTEMD'
---
# Calamares services-systemd module — Arch/CachyOS
# CRITICO: disabilita tutti i servizi live CachyOS/Arch nel sistema INSTALLATO.
# Questi servizi (nel squashfs) al primo boot rimuoverebbero /home e utenti.
services:
  - name: "NetworkManager"
    enabled: true
  - name: "cachyos-live"
    enabled: false
  - name: "cachyos-firstboot"
    enabled: false
  - name: "cachyos-configure-after-reboot"
    enabled: false
  - name: "archiso-reconfiguration"
    enabled: false
  - name: "archiso-keyring-populate"
    enabled: false
  - name: "archiso-copy-passwd"
    enabled: false
  - name: "archiso"
    enabled: false
  - name: "pacman-init"
    enabled: false
  - name: "clean-live"
    enabled: false
  - name: "livesys"
    enabled: false
  - name: "livesys-late"
    enabled: false
SVCSYSTEMD
    echo "[DC-Arch] ✓ services-systemd.conf: servizi live CachyOS disabilitati"
}

dc_remove_live_user() {
# ══════════════════════════════════════════════════════════════════════════════
# ARCH: dc-remove-live-user.sh = SOLO cleanup artefatti live
# NON rimuove utenti/home — quello lo fa il modulo users di Calamares.
# Questo shellprocess gira subito dopo unpackfs, PRIMA di initcpiocfg/initcpio/users.
# ══════════════════════════════════════════════════════════════════════════════
install -Dm755 /dev/stdin /usr/local/bin/dc-remove-live-user.sh << 'RMSCRIPT_ARCH'
#!/bin/bash
LOG="/var/log/dc-remove-live-user.log"
exec >"$LOG" 2>&1
echo "=== dc-remove-live-user [ARCH] $(date) ==="

# Tutti i path dove systemd cerca unit (incluso /lib che su alcune derivate è separato)
_SD_DIRS="/etc/systemd/system /usr/lib/systemd/system /lib/systemd/system"

# ══════════════════════════════════════════════════════════════════════════════
# 1. FIX MKINITCPIO.CONF — rimuovi hook archiso da conf + drop-in
# ══════════════════════════════════════════════════════════════════════════════
if [ -f /etc/mkinitcpio.conf ]; then
    echo "PRIMA HOOKS:"
    grep "^HOOKS=" /etc/mkinitcpio.conf || true

    for _hook in archiso_loop_mnt archiso_pxe_common archiso_pxe_nbd \
                 archiso_pxe_http archiso_pxe_nfs archiso_shutdown archiso_kms; do
        sed -i "s/ *${_hook}//g" /etc/mkinitcpio.conf
    done
    sed -i 's/ *archiso / /g'   /etc/mkinitcpio.conf
    sed -i 's/ *archiso)/)/g'   /etc/mkinitcpio.conf

    if ! grep -q 'autodetect' /etc/mkinitcpio.conf; then
        sed -i 's/^HOOKS=(\(.*\)udev /HOOKS=(\1udev autodetect modconf kms /' \
            /etc/mkinitcpio.conf
    fi
    sed -i 's/  */ /g; s/( /(/; s/ )/)/;' /etc/mkinitcpio.conf

    echo "DOPO HOOKS:"
    grep "^HOOKS=" /etc/mkinitcpio.conf || true
fi

# Fix 34 — Allineamento con live-side: rimuovi drop-in archiso.conf
# che aggiunge hook PXE (archiso_pxe_nbd/http/nfs) ignorando le pulizie
# fatte sopra su mkinitcpio.conf — senza questa rimozione dc-mkinitcpio.sh
# erediterebbe ancora i PXE hooks causando hang su nbd-client (timeout 300s)
if [ -d /etc/mkinitcpio.conf.d ]; then
    for _di in /etc/mkinitcpio.conf.d/*archiso*.conf; do
        [ -f "$_di" ] && rm -f "$_di" && echo "Rimosso drop-in: $_di"
    done
fi

# ══════════════════════════════════════════════════════════════════════════════
# 2. MASK home.mount — impedisce tmpfs su /home anche se un generator lo ricrea
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Bonifica mount unit e servizi live ==="

# 2a. Rimuovi E maschia home.mount + etc-pacman.d-gnupg.mount ovunque
for _UNIT in home.mount etc-pacman.d-gnupg.mount; do
    for _D in $_SD_DIRS; do
        [ -e "$_D/$_UNIT" ] && rm -f "$_D/$_UNIT" && echo "  RIMOSSO: $_D/$_UNIT"
    done
    # mask: crea symlink → /dev/null — impedisce avvio anche se un generator ricrea la unit
    systemctl mask "$_UNIT" 2>/dev/null && echo "  MASKED: $_UNIT" || true
done

# 2b. Rimuovi file noti live (autologin tty, script archiso)
for _F in \
    /etc/systemd/system/getty@tty1.service.d/autologin.conf \
    /etc/systemd/scripts/choose-mirror \
    /etc/systemd/scripts/livecd-talk; do
    [ -e "$_F" ] && rm -f "$_F" && echo "  RIMOSSO: $_F"
done

# 2c. Disabilita + rimuovi servizi per nome esatto da TUTTI i path systemd
for _SVC in \
    home.mount \
    etc-pacman.d-gnupg.mount \
    archiso-reconfiguration.service \
    archiso-keyring-populate.service \
    archiso-copy-passwd.service \
    archiso.service \
    pacman-init.service \
    clean-live.service \
    cachyos-live.service \
    cachyos-firstboot.service \
    cachyos-configure-after-reboot.service \
    cachyos-keyring.service \
    cachyos-rate-mirrors.service \
    reflector.service \
    livesys.service \
    livesys-late.service \
    live-config.service \
    livecd-alsa.service \
    livecd-talk.service; do
    systemctl disable "$_SVC" 2>/dev/null && echo "  DISABLED: $_SVC" || true
    for _D in $_SD_DIRS; do
        rm -f "$_D/$_SVC" 2>/dev/null
    done
done

# 2d. Discovery per pattern — TUTTI i path systemd incluso /lib, sia unit che *.wants
_DC_PATTERNS="*archiso* *pacman-init* *cachyos* clean-live* livesys* *livecd* *live-config*"
for _D in $_SD_DIRS; do
    [ -d "$_D" ] || continue
    # Unit/mount nella directory principale
    for _PAT in $_DC_PATTERNS; do
        for _F in "$_D"/$_PAT; do
            [ -e "$_F" ] || continue
            rm -f "$_F"
            echo "  RIMOSSO (discovery): $_F"
        done
    done
    # Symlink nelle subdirectory *.wants *.requires *.d
    for _W in "$_D"/*.wants "$_D"/*.requires; do
        [ -d "$_W" ] || continue
        for _PAT in $_DC_PATTERNS; do
            for _L in "$_W"/$_PAT; do
                [ -e "$_L" ] || continue
                rm -f "$_L"
                echo "  RIMOSSO wants: $_L"
            done
        done
    done
done

# 2e. MASK esplicito per service CachyOS pericolosi (symlink /dev/null)
# cachyos-configure-after-reboot e archiso-copy-passwd possono sovrascrivere
# /etc/shadow al primo boot, invalidando la password impostata da Calamares.
# Usare symlink /dev/null è più robusto di disable: impedisce l'avvio anche
# se un generator o un altro package ricrea la unit o il .wants symlink.
for _MSVC in \
    cachyos-configure-after-reboot.service \
    cachyos-firstboot.service \
    cachyos-live.service \
    archiso-copy-passwd.service \
    archiso-reconfiguration.service \
    archiso-keyring-populate.service \
    archiso.service \
    pacman-init.service; do
    # Rimuovi da tutti i path prima del mask
    for _D in $_SD_DIRS; do
        rm -f "$_D/$_MSVC" 2>/dev/null || true
        for _W in "$_D"/*.wants "$_D"/*.requires; do
            [ -d "$_W" ] && rm -f "$_W/$_MSVC" 2>/dev/null || true
        done
    done
    # Mask definitivo
    ln -sf /dev/null "/etc/systemd/system/$_MSVC" 2>/dev/null \
        && echo "  MASKED (null): $_MSVC" || true
done

# ══════════════════════════════════════════════════════════════════════════════
# 3. FIX /etc/fstab — rimuovi tmpfs /home dal live
# ══════════════════════════════════════════════════════════════════════════════
# Se il squashfs aveva tmpfs /home in fstab, Calamares fstab module potrebbe
# non averlo rimosso → systemd-fstab-generator crea home.mount a runtime
if [ -f /etc/fstab ]; then
    if grep -qE '^\s*tmpfs\s+/home\s' /etc/fstab; then
        echo "  WARN: trovato tmpfs /home in /etc/fstab — rimuovo"
        sed -i '/^\s*tmpfs\s\+\/home\s/d' /etc/fstab
    fi
    # Rimuovi anche eventuali mount overlay/aufs su /home
    if grep -qE '^\s*(overlay|aufs|unionfs)\s+/home\s' /etc/fstab; then
        echo "  WARN: trovato overlay /home in /etc/fstab — rimuovo"
        sed -i '/^\s*\(overlay\|aufs\|unionfs\)\s\+\/home\s/d' /etc/fstab
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# 4. AUTOLOGIN LIVE — rimuovi da display manager
# ══════════════════════════════════════════════════════════════════════════════
sed -i "/^autologin-user=/d;/^autologin-user-timeout=/d;/^autologin-session=/d" \
    /etc/lightdm/lightdm.conf 2>/dev/null || true
rm -f /etc/lightdm/lightdm.conf.d/50-distroClone-autologin.conf 2>/dev/null || true
rm -f /etc/sddm.conf.d/autologin.conf 2>/dev/null || true
sed -i "/^AutomaticLoginEnable=/d;/^AutomaticLogin=/d;/^TimedLoginEnable=/d" \
    /etc/gdm/custom.conf /etc/gdm3/custom.conf 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════
# 5. SAFETY NET + daemon-reload
# ══════════════════════════════════════════════════════════════════════════════
mkdir -p /home
echo 'd /home 0755 root root -' > /etc/tmpfiles.d/dc-home.conf
systemctl daemon-reload 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════
# 6. DIAGNOSTICA — dump stato per debug
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== Diagnostica post-cleanup ==="
echo "-- fstab (righe /home) --"
grep -i '/home' /etc/fstab 2>/dev/null || echo "  nessuna"
echo "-- mkinitcpio HOOKS --"
grep "^HOOKS=" /etc/mkinitcpio.conf 2>/dev/null || echo "  N/A"
echo "-- unit home.mount --"
systemctl cat home.mount 2>&1 | head -5 || echo "  masked/non trovata"
echo "-- systemd mount units attive --"
systemctl list-units --type=mount --no-pager 2>/dev/null | grep -i home || echo "  nessuna"

echo ""
echo "[DC] ✓ Cleanup artefatti archiso completato (NESSUN utente rimosso)"
echo "=== Fine ==="
RMSCRIPT_ARCH
}

dc_configure_family() {
    # dc-ensure-presets.sh
    install -Dm755 /dev/stdin /usr/local/bin/dc-ensure-presets.sh << 'PRESETSSCRIPT'
#!/bin/bash
# Eseguito da Calamares come shellprocess (chroot=true) nel sistema installato.
# Crea preset mkinitcpio per ogni kernel trovato in /boot/vmlinuz-* se assenti.
set -e

mkdir -p /etc/mkinitcpio.d

has_presets() {
    compgen -G '/etc/mkinitcpio.d/*.preset' > /dev/null 2>&1
}

if has_presets; then
    echo "[DC ensure-presets] Preset già presenti:"
    compgen -G '/etc/mkinitcpio.d/*.preset'
    exit 0
fi

echo "[DC ensure-presets] Nessun preset trovato — creo da /boot/vmlinuz-*"
_created=0
for _kf in /boot/vmlinuz-*; do
    [ -f "$_kf" ] || continue
    _kname=$(basename "$_kf" | sed 's/^vmlinuz-//')
    cat > "/etc/mkinitcpio.d/${_kname}.preset" << EOF
ALL_config='/etc/mkinitcpio.conf'
ALL_kver='/boot/vmlinuz-${_kname}'
PRESETS=('default' 'fallback')
default_image='/boot/initramfs-${_kname}.img'
fallback_image='/boot/initramfs-${_kname}-fallback.img'
fallback_options='-S autodetect'
EOF
    echo "[DC ensure-presets] Creato: ${_kname}.preset"
    _created=$((_created + 1))
done

if [ "$_created" -eq 0 ]; then
    echo "[DC ensure-presets] ERROR: nessun kernel trovato in /boot/vmlinuz-*"
    exit 1
fi

echo "[DC ensure-presets] Creati $_created preset(s)"
exit 0
PRESETSSCRIPT

    write_shellprocess_conf /etc/calamares/modules/dc-ensure-presets.conf false 60 \
        /usr/local/bin/dc-ensure-presets.sh

    echo "[DC] ✓ dc-ensure-presets configurato (Arch: preset mkinitcpio nel target)"

    # dc-mkinitcpio.sh — Fix 32: sempre shellprocess per Arch
    install -Dm755 /dev/stdin /usr/local/bin/dc-mkinitcpio.sh << 'MKINITCPIO_SCRIPT'
#!/bin/bash
# dc-mkinitcpio.sh — ricostruzione initramfs nel TARGET installato (Calamares shellprocess)
# Fix 34: output su stdout per evitare timeout Calamares
# Fix 45B: sostituisce HOOKS live (archiso/squashfs) con set standard sistema installato
#          archiso hook nel TARGET cerca l'ISO via blkid → hang 90s senza output
set -e
echo "=== dc-mkinitcpio $(date) ==="

# Rimuove drop-in archiso.conf e varianti (PXE hooks bloccanti)
rm -f /etc/mkinitcpio.conf.d/*archiso*.conf 2>/dev/null || true

# Fix 45B: sostituisce HOOKS e MODULES nel sistema installato.
# Nel LIVE: HOOKS=(base udev archiso block filesystems keyboard fsck)
#           MODULES=(squashfs loop isofs overlay sr_mod cdrom)
# Nel TARGET installato: archiso hook cerca il device live → hang/timeout.
#   Soluzione: standard hooks senza archiso + MODULES vuoto (autodetect pensa a tutto).
if [ -f /etc/mkinitcpio.conf ]; then
    sed -i \
        -e 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' \
        -e 's/^MODULES=.*/MODULES=()/' \
        /etc/mkinitcpio.conf
    echo "HOOKS aggiornati per sistema installato (rimosso archiso, MODULES svuotato)"
fi
echo "--- HOOKS ---"
grep "^HOOKS=" /etc/mkinitcpio.conf 2>/dev/null || echo "  file non trovato"

# Verifica/crea preset
if ! compgen -G '/etc/mkinitcpio.d/*.preset' > /dev/null 2>&1; then
    echo "WARN: nessun preset in /etc/mkinitcpio.d/ — creo dal kernel"
    mkdir -p /etc/mkinitcpio.d
    for _kfile in /boot/vmlinuz-*; do
        [ -f "$_kfile" ] || continue
        _kname=$(basename "$_kfile" | sed 's/^vmlinuz-//')
        cat > "/etc/mkinitcpio.d/${_kname}.preset" << MKPRESET
ALL_config='/etc/mkinitcpio.conf'
ALL_kver='/boot/vmlinuz-${_kname}'
PRESETS=('default')
default_image='/boot/initramfs-${_kname}.img'
MKPRESET
        echo "  Preset: $_kname"
    done
fi

# -v produce output continuo → Calamares non va in timeout per assenza output
echo "--- mkinitcpio -P -v ---"
mkinitcpio -P -v
echo "--- initramfs generati ---"
ls -lh /boot/initramfs-*.img 2>/dev/null || echo "  nessuno trovato"
echo "=== dc-mkinitcpio completato ==="
MKINITCPIO_SCRIPT

    # Timeout 300s: mkinitcpio -v su sistemi con molti moduli può richiedere 2-3 min
    write_shellprocess_conf /etc/calamares/modules/dc-mkinitcpio.conf false 300 \
        /usr/local/bin/dc-mkinitcpio.sh

    echo "[DC] ✓ dc-mkinitcpio configurato (Fix 32 — sempre shellprocess per Arch)"

    # Fix 33: per Arch creare SEMPRE dc-services.sh (mai usare modulo C++ services-systemd)
    # Disabilita servizi live Arch/CachyOS/Manjaro nel sistema installato.
    # Eseguito nel TARGET (dontChroot: false) dal modulo shellprocess.
    install -Dm755 /dev/stdin /usr/local/bin/dc-services.sh << 'DCSVC_SCRIPT'
#!/bin/bash
# dc-services.sh — Fix 33: sostituto shellprocess per services-systemd su Arch
# Eseguito nel TARGET (chroot installato) da Calamares shellprocess.
# Gestisce enable/disable servizi live senza dipendere dal modulo C++ services-systemd.
LOG="/var/log/dc-services.log"
exec >"$LOG" 2>&1
echo "=== dc-services [Fix 33] $(date) ==="

_svc_enable()  { systemctl enable  "$1" 2>/dev/null && echo "  enabled:  $1" || echo "  skip: $1 (non trovato)"; }
_svc_disable() { systemctl disable "$1" 2>/dev/null && echo "  disabled: $1" || echo "  skip: $1 (non trovato)"; }
# _svc_mask: disable + rimuovi unit + symlink /dev/null (impedisce avvio anche con static .wants)
_svc_mask() {
    systemctl disable "$1" 2>/dev/null || true
    for _d in /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
        rm -f "$_d/$1" "$_d/${1%.service}.d" 2>/dev/null || true
        # Rimuovi symlink .wants/.requires che puntano a questo service
        for _w in "$_d"/*.wants "$_d"/*.requires; do
            [ -d "$_w" ] && rm -f "$_w/$1" 2>/dev/null || true
        done
    done
    ln -sf /dev/null "/etc/systemd/system/$1" 2>/dev/null && echo "  masked: $1" || echo "  skip mask: $1"
}

# Abilita servizi essenziali
_svc_enable NetworkManager

# MASK (non solo disable) i servizi CachyOS/Arch pericolosi che modificano utenti/shadow.
# cachyos-configure-after-reboot e archiso-copy-passwd possono sovrascrivere /etc/shadow
# al primo boot, invalidando la password impostata da Calamares.
_svc_mask cachyos-configure-after-reboot.service
_svc_mask cachyos-firstboot.service
_svc_mask cachyos-live.service
_svc_mask archiso-copy-passwd.service
_svc_mask archiso-reconfiguration.service
_svc_mask archiso-keyring-populate.service
_svc_mask archiso.service
_svc_mask pacman-init.service
# Disabilita (non mask) i restanti servizi live
_svc_disable clean-live
_svc_disable livesys
_svc_disable livesys-late
# Manjaro-specifici
_svc_disable mhwd-live
_svc_disable manjaro-live
_svc_disable systemd-networkd   # Manjaro usa NM, non networkd

echo "=== dc-services completato ==="
DCSVC_SCRIPT

    write_shellprocess_conf /etc/calamares/modules/dc-services.conf false 60 \
        /usr/local/bin/dc-services.sh

    echo "[DC] ✓ dc-services configurato (Fix 33 — sempre shellprocess per Arch)"

    # ── Fix Arch HW reale: path squashfs dinamico per unpackfs.conf ──────────────
    # Su HW reale (Garuda, EndeavourOS, e altri Arch) il path standard
    # /run/archiso/bootmnt/arch/<arch>/airootfs.sfs non è sempre raggiungibile
    # quando Calamares legge unpackfs.conf (es. copytoram, timing USB, ecc.).
    # Un systemd service rileva il path reale al boot della live e aggiorna
    # unpackfs.conf PRIMA che l'utente avvii l'installazione.
    # ConditionKernelCommandLine=archisobasedir garantisce che il service
    # NON giri nel sistema installato (il kernel param esiste solo nella live).
    echo "[DC-Arch] Scrittura dc-fix-unpackfs.sh + service (tutti Arch)"

    install -Dm755 /dev/stdin /usr/local/bin/dc-fix-unpackfs.sh << 'FIX_UNPACKFS_SCRIPT'
#!/bin/bash
# dc-fix-unpackfs.sh — DistroClone Arch live
# Rileva il path reale del squashfs e aggiorna unpackfs.conf prima
# che Calamares esegua il modulo unpackfs.
# Eseguito da dc-fix-unpackfs.service al boot della live.
# Attivato solo se il kernel param "archisobasedir" è presente (live only).

_ARCH=$(uname -m)
_UNPACK_CONF="/etc/calamares/modules/unpackfs.conf"
_DEFAULT="/run/archiso/bootmnt/arch/${_ARCH}/airootfs.sfs"

# Path default già accessibile → nulla da fare
if [ -f "$_DEFAULT" ]; then
    echo "[dc-fix-unpackfs] Path default OK: $_DEFAULT"
    exit 0
fi

echo "[dc-fix-unpackfs] Path default non trovato: $_DEFAULT"
echo "[dc-fix-unpackfs] Ricerca path alternativo..."

_FOUND=""
_SRC_VAL=""   # valore da inserire in source: (path file tra virgolette o device nudo)

# 1. Varianti note del path archiso/miso/copytoram
for _p in \
    "/run/archiso/bootmnt/arch/${_ARCH}/airootfs.sfs" \
    "/run/archiso/bootmnt/${_ARCH}/airootfs.sfs" \
    "/run/archiso/airootfs.sfs" \
    "/run/archiso/copytoram/airootfs.sfs" \
    "/run/miso/bootmnt/arch/${_ARCH}/airootfs.sfs"; do
    if [ -f "$_p" ]; then _FOUND="$_p"; _SRC_VAL="\"${_p}\""; break; fi
done

# 2. find generico sotto /run (maxdepth contenuto)
if [ -z "$_FOUND" ]; then
    _FOUND=$(find /run -maxdepth 8 -name "airootfs.sfs" 2>/dev/null | head -1)
    [ -n "$_FOUND" ] && _SRC_VAL="\"${_FOUND}\""
fi

# 3. Backing file accessibile dei loop device (qualsiasi .sfs/.squashfs)
if [ -z "$_FOUND" ]; then
    while IFS= read -r _bk; do
        [ -f "$_bk" ] && { _FOUND="$_bk"; _SRC_VAL="\"${_bk}\""; break; }
    done < <(losetup -l -n -O BACK-FILE 2>/dev/null | grep -E "\.(sfs|squashfs)$")
fi

# 4. Fallback: usa il loop device direttamente (copytoram: backing file in RAM,
#    path non più accessibile su disco ma il device è leggibile da calamares)
if [ -z "$_FOUND" ]; then
    while IFS=' ' read -r _dev _bk; do
        if echo "$_bk" | grep -qE "\.(sfs|squashfs)"; then
            _FOUND="$_dev"; _SRC_VAL="${_dev}"; break
        fi
    done < <(losetup -l -n -O NAME,BACK-FILE 2>/dev/null)
fi

if [ -n "$_SRC_VAL" ]; then
    echo "[dc-fix-unpackfs] ✓ Squashfs trovato: $_FOUND"
    sed -i "s|source:.*|source: ${_SRC_VAL}|" "$_UNPACK_CONF"
    echo "[dc-fix-unpackfs] ✓ unpackfs.conf aggiornato"
else
    echo "[dc-fix-unpackfs] WARN: squashfs non trovato in nessun path noto"
    echo "  /run/archiso : $(ls /run/archiso/ 2>/dev/null || echo 'non esiste')"
    echo "  losetup      : $(losetup -l 2>/dev/null || echo 'N/A')"
fi
FIX_UNPACKFS_SCRIPT

    cat > /etc/systemd/system/dc-fix-unpackfs.service << 'FIX_UNPACKFS_SVC'
[Unit]
Description=DistroClone: rileva path squashfs reale per unpackfs.conf (Arch live)
# ConditionKernelCommandLine: il param "archisobasedir" esiste SOLO nella live.
# Nel sistema installato il service è silenziosamente saltato → nessuna regressione.
ConditionKernelCommandLine=archisobasedir
DefaultDependencies=no
After=local-fs.target
Before=graphical.target display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dc-fix-unpackfs.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
FIX_UNPACKFS_SVC

    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /etc/systemd/system/dc-fix-unpackfs.service \
           /etc/systemd/system/multi-user.target.wants/dc-fix-unpackfs.service \
           2>/dev/null || true
    echo "[DC-Arch] ✓ dc-fix-unpackfs.service abilitato (Arch famiglia completa)"
    # ── fine blocco fix squashfs ───────────────────────────────────────────────
}

dc_settings_conf() {
    # Rilevamento moduli
    HAS_LOCALECFG=0
    if [ -f "${CAL_MODULES}/localecfg/module.desc" ] || \
       [ -f "/usr/lib/calamares/modules/localecfg/module.desc" ] || \
       [ -f "/usr/lib64/calamares/modules/localecfg/module.desc" ]; then
        HAS_LOCALECFG=1
    fi

    # Fix 32: controllare main.py o *.so — solo presenza directory/module.desc
    # genera falsi positivi su EndeavourOS/chaotic-aur dove il modulo esiste
    # ma non si carica (manca l'implementazione Python o .so).
    HAS_INITCPIOCFG=0
    for _d in "${CAL_MODULES}/initcpiocfg" "/usr/lib/calamares/modules/initcpiocfg" \
              "/usr/lib64/calamares/modules/initcpiocfg"; do
        if [ -f "$_d/main.py" ] || ls "$_d"/*.so >/dev/null 2>&1; then
            HAS_INITCPIOCFG=1; break
        fi
    done

    # Fix 32: per Arch usiamo SEMPRE shellprocess@dc-mkinitcpio al posto del
    # modulo C++ initcpio — elimina falsi positivi su EndeavourOS/chaotic-aur
    # dove la directory initcpio/ esiste ma il modulo non si carica.
    # Su CachyOS/Garuda dc-mkinitcpio esegue mkinitcpio -P che è equivalente.
    HAS_INITCPIO=0   # non più usato per la sequenza Arch
    echo "  initcpiocfg module: ${HAS_INITCPIOCFG} | initcpio: sempre shellprocess (Fix 32)"

    # Fix 33: Arch usa SEMPRE shellprocess@dc-services (mai modulo C++ services-systemd)
    HAS_SERVICES_SYSTEMD=0
    echo "  services-systemd module: ${HAS_SERVICES_SYSTEMD} (Fix 33 — Arch: sempre shellprocess)"

    settings_begin

    settings_add_instance "dc-post-users" "dc-post-users.conf"
    settings_add_instance "dc-ensure-presets" "dc-ensure-presets.conf"
    settings_add_instance "dc-mkinitcpio" "dc-mkinitcpio.conf"
    settings_add_instance "dc-services" "dc-services.conf"  # Fix 33

    settings_begin_sequence

    if [ "$HAS_LOCALECFG" -eq 1 ]; then
        settings_exec_add "localecfg"
    fi

    settings_exec_add "shellprocess@dc-ensure-presets"
    if [ "$HAS_INITCPIOCFG" -eq 1 ]; then
        settings_exec_add "initcpiocfg"
    fi
    # Fix 32: sempre shellprocess@dc-mkinitcpio, mai modulo initcpio C++
    settings_exec_add "shellprocess@dc-mkinitcpio"
    settings_exec_add "users"
    settings_exec_add "shellprocess@dc-post-users"
    settings_exec_add "displaymanager"
    settings_exec_add "networkcfg"
    settings_exec_add "hwclock"
    # Fix 33: Arch usa SEMPRE shellprocess@dc-services (mai modulo C++ services-systemd)
    # su Manjaro/EndeavourOS/chaotic-aur il modulo C++ non si carica.
    settings_exec_add "shellprocess@dc-services"
    settings_exec_add "shellprocess@grubinstall"
    settings_exec_add "umount"

    settings_finish
}
