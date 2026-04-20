#!/bin/bash
# =============================================================================
# build-appimage.sh — Costruisce distroClone-x86_64.AppImage
# =============================================================================
# Ispirato a penguins-eggs AppImage workflow (MIT - Piero Proietti)
# Adattato per DistroClone by Franco Conidi aka edmond <fconidi@gmail.com>
#
# Filosofia (uguale a penguins-eggs):
#   - L'AppImage contiene SOLO gli script bash di DistroClone
#   - NON bundla tool di sistema (xorriso, grub, squashfs-tools, ecc.)
#   - Al primo avvio usa dc_bootstrap() per installare le dipendenze
#     tramite il package manager nativo (apt/pacman/dnf/zypper)
#   - Risultato: un singolo file .AppImage funzionante su tutte le distro
#
# Uso:
#   chmod +x build-appimage.sh
#   bash build-appimage.sh [--version 1.3.6] [--output /percorso/output]
#
# Prerequisiti (installati automaticamente se mancanti su Debian):
#   - mksquashfs (squashfs-tools)
#   - wget o curl
#   - file
# =============================================================================

set -euo pipefail

# ── Parametri ────────────────────────────────────────────────────────────────
DC_VERSION="${DC_VERSION:-1.3.6}"
DC_ARCH="${DC_ARCH:-x86_64}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)}"
APPIMAGE_NAME="distroClone-${DC_VERSION}-${DC_ARCH}.AppImage"

# Sorgenti — percorso degli script da includere nell'AppImage
# Cerca prima nella directory dello script, poi in /usr/share/distroClone
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES=(
    "${SCRIPT_DIR}/DistroClone.sh"
    "/usr/share/distroClone/DistroClone.sh"
)
DETECT_SOURCES=(
    "${SCRIPT_DIR}/distro-detect.sh"
    "/usr/share/distroClone/distro-detect.sh"
)
CALCONF_SOURCES=(
    "${SCRIPT_DIR}/calamares-config.sh"
    "/usr/share/distroClone/calamares-config.sh"
)

# URL runtime AppImage type2 (scaricato da GitHub al momento del build)
RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-${DC_ARCH}"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${DC_ARCH}.AppImage"

# ── Colori e helper ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; exit 1; }

WORKDIR="$(mktemp -d /tmp/dc-appimage-build-XXXX)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# Argomenti CLI
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) DC_VERSION="$2"; APPIMAGE_NAME="distroClone-${DC_VERSION}-${DC_ARCH}.AppImage"; shift 2 ;;
        --output)  OUTPUT_DIR="$2"; shift 2 ;;
        --arch)    DC_ARCH="$2"; shift 2 ;;
        -h|--help)
            echo "Uso: $0 [--version VERSION] [--output DIR] [--arch ARCH]"
            echo "  --version  Versione da inserire nell'AppImage (default: 1.3.6)"
            echo "  --output   Directory di output (default: pwd)"
            echo "  --arch     Architettura: x86_64 | aarch64 (default: x86_64)"
            exit 0 ;;
        *) warn "Argomento sconosciuto: $1" ;;
    esac
done

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  DistroClone AppImage Builder v${DC_VERSION}${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
info "Versione  : $DC_VERSION"
info "Architettura: $DC_ARCH"
info "Output    : $OUTPUT_DIR/${APPIMAGE_NAME}"
info "Workdir   : $WORKDIR"
echo ""

# =============================================================================
# 1. Prerequisiti
# =============================================================================
echo -e "${BOLD}[1/6] Verifica prerequisiti${NC}"

install_if_missing() {
    local pkg="$1" cmd="${2:-$1}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "$cmd non trovato — installazione..."
        # Serve root per installare pacchetti
        local SUDO=""
        [ "$(id -u)" -ne 0 ] && SUDO="sudo"
        if command -v apt-get >/dev/null 2>&1; then
            $SUDO apt-get install -y "$pkg" || die "Impossibile installare $pkg — esegui: sudo apt-get install $pkg"
        elif command -v pacman >/dev/null 2>&1; then
            $SUDO pacman -S --noconfirm "$pkg" || die "Impossibile installare $pkg — esegui: sudo pacman -S $pkg"
        elif command -v dnf >/dev/null 2>&1; then
            $SUDO dnf install -y "$pkg" || die "Impossibile installare $pkg — esegui: sudo dnf install $pkg"
        elif command -v zypper >/dev/null 2>&1; then
            $SUDO zypper install -y "$pkg" || die "Impossibile installare $pkg — esegui: sudo zypper install $pkg"
        else
            die "Installa manualmente: $pkg"
        fi
    fi
    ok "$cmd disponibile"
}

install_if_missing "squashfs-tools" "mksquashfs"
install_if_missing "wget" "wget"
install_if_missing "file" "file"

# Downloader generico
download() {
    local url="$1" dest="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$url" -O "$dest" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar "$url" -o "$dest" || return 1
    else
        die "wget o curl richiesti"
    fi
}

# =============================================================================
# 2. Localizza script sorgente
# =============================================================================
echo -e "\n${BOLD}[2/6] Localizza script sorgente${NC}"

find_script() {
    local varname="$1"; shift
    for candidate in "$@"; do
        if [ -f "$candidate" ]; then
            printf -v "$varname" '%s' "$candidate"
            ok "Trovato: $candidate"
            return 0
        fi
    done
    die "Nessuno script trovato tra: $*"
}

find_script MAIN_SH        "${SOURCES[@]}"
find_script DETECT_SH      "${DETECT_SOURCES[@]}"
find_script CALCONF_SH     "${CALCONF_SOURCES[@]}"

# Asset sorgente — cerca nella directory sibling distroclone-fedora
DC_ASSET_SRC="${SCRIPT_DIR}/../distroclone-fedora/distroClone_1.3.6_all"
# Fallback a versione precedente se la corrente non esiste ancora
[ -d "$DC_ASSET_SRC" ] || DC_ASSET_SRC="${SCRIPT_DIR}/../distroclone-fedora/distroClone_1.3.5_all"

# Icona — cerca in sorgente sibling, poi posizioni standard
ICON_FILE=""
for icon_candidate in \
    "${DC_ASSET_SRC}/usr/share/icons/hicolor/256x256/apps/distroClone.png" \
    "${DC_ASSET_SRC}/usr/share/distroClone/distroClone-logo.png" \
    "${SCRIPT_DIR}/distroClone.png" \
    "/usr/share/icons/hicolor/256x256/apps/distroClone.png" \
    "/usr/share/distroClone/distroClone-logo.png"; do
    if [ -f "$icon_candidate" ]; then
        ICON_FILE="$icon_candidate"
        ok "Icona: $icon_candidate"
        break
    fi
done
[ -z "$ICON_FILE" ] && warn "Icona non trovata — verrà usata una generica"

# =============================================================================
# 3. Costruisce AppDir
# =============================================================================
echo -e "\n${BOLD}[3/6] Costruisce AppDir${NC}"

APPDIR="$WORKDIR/AppDir"
mkdir -p "$APPDIR"/{usr/bin,usr/share/distroClone,usr/share/applications}
mkdir -p "$APPDIR"/usr/share/icons/hicolor/{48x48,128x128,256x256}/apps

# Copia icone hicolor da sorgente sibling
DC_DEB_ICONS="${DC_ASSET_SRC}/usr/share/icons/hicolor"
for size in 48x48 128x128 256x256; do
    src="${DC_DEB_ICONS}/${size}/apps/distroClone.png"
    if [ -f "$src" ]; then
        cp "$src" "$APPDIR/usr/share/icons/hicolor/${size}/apps/distroClone.png"
        ok "Icona ${size} copiata"
    fi
done

# Copia script — cross-distro: solo Arch + Fedora (no debian)
cp "$MAIN_SH"    "$APPDIR/usr/share/distroClone/DistroClone.sh"
cp "$DETECT_SH"  "$APPDIR/usr/share/distroClone/distro-detect.sh"
cp "$CALCONF_SH" "$APPDIR/usr/share/distroClone/calamares-config.sh"
for _cc_mod in calamares-config-arch.sh calamares-config-fedora.sh \
               dc-crypto.sh dc-initramfs.sh dc-grub.sh; do
    [ -f "${SCRIPT_DIR}/${_cc_mod}" ] && \
        cp "${SCRIPT_DIR}/${_cc_mod}" "$APPDIR/usr/share/distroClone/${_cc_mod}" && \
        chmod 755 "$APPDIR/usr/share/distroClone/${_cc_mod}" || true
done
chmod 755 "$APPDIR/usr/share/distroClone/"*.sh
ok "Script copiati (Arch + Fedora + dc-crypto layer)"


# Copia loghi personalizzati — sorgente sibling
LOGO_SOURCES=(
    "${DC_ASSET_SRC}/usr/share/distroClone"
    "/usr/share/distroClone"
    "${SCRIPT_DIR}"
)
for logo_dir in "${LOGO_SOURCES[@]}"; do
    for logo in distroClone-logo.png distroClone-welcome.png distroClone-installer.png; do
        if [ -f "${logo_dir}/${logo}" ] && [ ! -f "$APPDIR/usr/share/distroClone/${logo}" ]; then
            cp "${logo_dir}/${logo}" "$APPDIR/usr/share/distroClone/${logo}"
            ok "Logo copiato: ${logo}"
        fi
    done
done

# Icona
if [ -n "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APPDIR/usr/share/icons/hicolor/256x256/apps/distroClone.png"
    cp "$ICON_FILE" "$APPDIR/distroClone.png"
else
    # Crea icona placeholder 1x1 PNG (base64)
    printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' \
        | base64 -d > "$APPDIR/distroClone.png"
    cp "$APPDIR/distroClone.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/distroClone.png"
fi
ok "Icona configurata"

# .desktop file (obbligatorio per AppImage)
cat > "$APPDIR/distroClone.desktop" << DESKTOP
[Desktop Entry]
Name=DistroClone
GenericName=Live ISO Builder
Comment=Create bootable live ISO images from any running Linux system
Exec=distroClone
Icon=distroClone
Type=Application
Categories=System;Administration;
Keywords=iso;live;backup;clone;installer;
StartupNotify=false
Terminal=false
Version=${DC_VERSION}
DESKTOP
cp "$APPDIR/distroClone.desktop" "$APPDIR/usr/share/applications/distroClone.desktop"
ok ".desktop creato"

# ── AppRun — entry point dell'AppImage ───────────────────────────────────────
# Ispirato a penguins-eggs AppRun: sorgenta i moduli, poi lancia l'app principale
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
# =============================================================================
# DistroClone AppRun — entry point AppImage
# =============================================================================

# NON usare set -e qui: causa uscite silenziose durante dc_bootstrap
# che fa fallire la copia dei file in DC_TMP

# APPDIR è impostato dal runtime AppImage al mount point del filesystem
APPDIR="${APPDIR:-$(dirname "$(readlink -f "$0")")}"
DC_SHARE_APPIMAGE="${APPDIR}/usr/share/distroClone"

# ── Verifica root ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo ""
    echo "  DistroClone richiede i privilegi di root."
    echo "  Uso: sudo $(basename "$0")"
    echo ""
    # Preserva variabili display per YAD/Zenity sotto sudo
    _DISPLAY="${DISPLAY:-}"
    _WAYLAND="${WAYLAND_DISPLAY:-}"
    _XAUTH="${XAUTHORITY:-}"
    _DBUS="${DBUS_SESSION_BUS_ADDRESS:-}"

    if [ -n "${_DISPLAY}${_WAYLAND}" ] && command -v pkexec >/dev/null 2>&1; then
        exec pkexec --disable-internal-agent             env DISPLAY="${_DISPLAY}"                 WAYLAND_DISPLAY="${_WAYLAND}"                 XAUTHORITY="${_XAUTH}"                 DBUS_SESSION_BUS_ADDRESS="${_DBUS}"                 APPDIR="${APPDIR}"             "$0" "$@"
    else
        exec sudo -E             APPDIR="${APPDIR}"             DISPLAY="${_DISPLAY}"             WAYLAND_DISPLAY="${_WAYLAND}"             XAUTHORITY="${_XAUTH}"             DBUS_SESSION_BUS_ADDRESS="${_DBUS}"             "$0" "$@"
    fi
fi

# ── Copia IMMEDIATA degli script in /tmp (prima di qualsiasi altra cosa) ──────
# CRITICO: deve avvenire PRIMA di dc_bootstrap e PRIMA del check root/sudo.
# Motivo: il FUSE mount può scollegarsi durante operazioni lunghe.
# Motivo 2: set -e + dc_bootstrap che fallisce causerebbe uscita prima della copia.
DC_TMP="$(mktemp -d /tmp/distroClone-run-XXXX)"

# Copia con verifica esplicita di ogni file
_dc_copy() {
    local src="${DC_SHARE_APPIMAGE}/$1"
    local dst="${DC_TMP}/$1"
    # Prova nome esatto
    if [ -f "$src" ]; then
        cp "$src" "$dst" && chmod 755 "$dst" && return 0
    fi
    # Fallback glob: accetta varianti tipo calamares-config-4.sh
    local found
    found="$(find "${DC_SHARE_APPIMAGE}" -maxdepth 1 -name "${1%.sh}*.sh" 2>/dev/null | sort | head -n1)"
    if [ -n "$found" ] && [ -f "$found" ]; then
        cp "$found" "$dst" && chmod 755 "$dst" && return 0
    fi
    # Fallback: /usr/share/distroClone (se .deb installato)
    local fallback="/usr/share/distroClone/$1"
    if [ -f "$fallback" ]; then
        cp "$fallback" "$dst" && chmod 755 "$dst" && return 0
    fi
    echo "[AppRun ERROR] File non trovato: $1"
    echo "  Cercato in: $src"
    echo "  Glob:       ${DC_SHARE_APPIMAGE}/${1%.sh}*.sh → $found"
    echo "  Fallback:   $fallback"
    echo "  Contenuto DC_SHARE_APPIMAGE:"
    ls -la "${DC_SHARE_APPIMAGE}/" 2>/dev/null || echo "  (directory non accessibile)"
    rm -rf "$DC_TMP"
    exit 1
}

_dc_copy "DistroClone.sh"
_dc_copy "distro-detect.sh"
_dc_copy "calamares-config.sh"
_dc_copy "calamares-config-arch.sh"    || true
_dc_copy "calamares-config-fedora.sh"  || true
_dc_copy "dc-crypto.sh"               || true
_dc_copy "dc-initramfs.sh"            || true
_dc_copy "dc-grub.sh"                 || true

# Copia loghi (opzionali — nessun errore se mancano)
for logo in distroClone-logo.png distroClone-welcome.png distroClone-installer.png; do
    [ -f "${DC_SHARE_APPIMAGE}/${logo}" ] && cp "${DC_SHARE_APPIMAGE}/${logo}" "${DC_TMP}/${logo}" || true
done



# DC_SHARE punta ora a /tmp — indipendente dal FUSE mount
export DC_SHARE="${DC_TMP}"
export DC_APPIMAGE_MODE=1
export APPDIR

# ── Bootstrap dipendenze (dopo la copia, errori non fatali) ───────────────────
DC_DETECT="${DC_TMP}/distro-detect.sh"
if [ -f "$DC_DETECT" ]; then
    source "$DC_DETECT" 2>/dev/null || true
    dc_bootstrap 2>/dev/null || true
fi

# ── Gestione argomenti speciali AppImage ──────────────────────────────────────
case "${1:-}" in
    --version)
        grep -m1 "^DC_VERSION\|^VERSION\|^SCRIPT_VERSION"             "${DC_TMP}/DistroClone.sh" 2>/dev/null | head -1             || echo "DistroClone ${APPIMAGE_VERSION:-unknown}"
        rm -rf "${DC_TMP}"; exit 0 ;;
    --install-deps)
        [ -f "$DC_DETECT" ] && source "$DC_DETECT" && dc_install_dependencies
        rm -rf "${DC_TMP}"; exit 0 ;;
    --detect)
        [ -f "$DC_DETECT" ] && source "$DC_DETECT" && dc_detect_distro && dc_print_distro_info
        rm -rf "${DC_TMP}"; exit 0 ;;
esac

# ── Avvia DistroClone da /tmp ─────────────────────────────────────────────────
bash "${DC_TMP}/DistroClone.sh" "$@"
EXIT_CODE=$?
rm -rf "${DC_TMP}"
exit ${EXIT_CODE}
APPRUN


chmod +x "$APPDIR/AppRun"
ok "AppRun creato"

# Symlink /usr/bin/distroClone → AppRun (per PATH lookup all'interno dell'AppImage)
ln -sf "../../AppRun" "$APPDIR/usr/bin/distroClone"
ok "Symlink usr/bin/distroClone → AppRun"

# ── Riepilogo AppDir ──────────────────────────────────────────────────────────
echo ""
info "Struttura AppDir:"
find "$APPDIR" -type f | sort | sed "s|$APPDIR|  |"

# =============================================================================
# 4. Scarica appimagetool e runtime
# =============================================================================
echo -e "\n${BOLD}[4/6] Scarica appimagetool e runtime AppImage type2${NC}"

APPIMAGETOOL_BIN="$WORKDIR/appimagetool"
RUNTIME_BIN="$WORKDIR/runtime-${DC_ARCH}"

info "Scarico runtime type2..."
download "$RUNTIME_URL" "$RUNTIME_BIN" \
    || die "Impossibile scaricare il runtime: $RUNTIME_URL"
chmod +x "$RUNTIME_BIN"
[ -s "$RUNTIME_BIN" ] || die "Runtime scaricato è vuoto"
ok "Runtime: $RUNTIME_BIN ($(wc -c < "$RUNTIME_BIN") bytes)"

info "Scarico appimagetool..."
download "$APPIMAGETOOL_URL" "$APPIMAGETOOL_BIN" \
    || die "Impossibile scaricare appimagetool: $APPIMAGETOOL_URL"
chmod +x "$APPIMAGETOOL_BIN"
[ -s "$APPIMAGETOOL_BIN" ] || die "appimagetool scaricato è vuoto"
ok "appimagetool: $(wc -c < "$APPIMAGETOOL_BIN") bytes"

# =============================================================================
# 5. Assembla AppImage
# =============================================================================
echo -e "\n${BOLD}[5/6] Assembla AppImage${NC}"

APPIMAGE_OUT="${OUTPUT_DIR}/${APPIMAGE_NAME}"
mkdir -p "$OUTPUT_DIR"

# Metodo penguins-eggs: mksquashfs + cat runtime + squashfs = AppImage
# Questo metodo NON richiede FUSE per il build (solo per l'esecuzione sull'host)
SQUASHFS_FILE="$WORKDIR/AppDir.squashfs"

info "Compressione AppDir con mksquashfs (zstd)..."
mksquashfs "$APPDIR" "$SQUASHFS_FILE" \
    -root-owned \
    -noappend \
    -comp zstd \
    -Xcompression-level 19 \
    -noI -noX \
    >/dev/null 2>&1
ok "SquashFS: $(du -sh "$SQUASHFS_FILE" | cut -f1)"

info "Assemblaggio AppImage: runtime + squashfs..."
cat "$RUNTIME_BIN" "$SQUASHFS_FILE" > "$APPIMAGE_OUT"
chmod a+x "$APPIMAGE_OUT"
ok "AppImage assemblato: $APPIMAGE_OUT"

# =============================================================================
# 6. Verifica finale
# =============================================================================
echo -e "\n${BOLD}[6/6] Verifica${NC}"

APPIMAGE_SIZE=$(du -sh "$APPIMAGE_OUT" | cut -f1)
ok "File: $APPIMAGE_OUT"
ok "Dimensione: $APPIMAGE_SIZE"

# Verifica magic bytes AppImage type2 (0x41 0x49 0x02 in posizione 8-10)
MAGIC=$(xxd -l 12 "$APPIMAGE_OUT" 2>/dev/null | head -1)
info "Magic bytes: $MAGIC"

# Testa --appimage-extract-and-run se disponibile (bypass FUSE per il test)
if APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE_OUT" --version >/dev/null 2>&1; then
    ok "AppImage avviabile (--version test OK)"
elif "$APPIMAGE_OUT" --appimage-extract >/dev/null 2>&1; then
    ok "AppImage estraibile (FUSE non disponibile ma AppImage valido)"
    rm -rf squashfs-root 2>/dev/null || true
else
    warn "Test esecuzione non disponibile (FUSE richiesto sul target)"
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  BUILD COMPLETATO                                    ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${NC}"
printf "║  File    : %-42s║\n" "$APPIMAGE_NAME"
printf "║  Versione: %-42s║\n" "$DC_VERSION"
printf "║  Size    : %-42s║\n" "$APPIMAGE_SIZE"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Uso:"
echo "    sudo ./${APPIMAGE_NAME}              # avvia DistroClone"
echo "    sudo ./${APPIMAGE_NAME} --detect     # mostra famiglia distro"
echo "    sudo ./${APPIMAGE_NAME} --install-deps # installa dipendenze"
echo "    ./${APPIMAGE_NAME} --appimage-extract # estrai contenuto"
echo ""
