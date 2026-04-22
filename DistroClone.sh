#!/bin/bash
# ── AppImage / path compatibility ────────────────────────────────────────────
# Priority: 1) DC_SHARE from environment (AppImage/AppRun)
#            2) Script's own directory (extracted AppImage, development)
#            3) /usr/share/distroClone (.deb installation)
_DC_SELF_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# Determine DC_SHARE in priority order:
# 1) _DC_SELF_DIR (AppImage/DC_TMP from AppRun, development, .deb) — only distro-detect.sh needed
# 2) DC_SHARE from environment (AppRun) — only distro-detect.sh needed
# 3) APPDIR/usr/share/distroClone (AppImage FUSE mount, pkexec without env)
# 4) /usr/share/distroClone (fallback .deb installation)
if [ -f "${_DC_SELF_DIR}/distro-detect.sh" ]; then
    DC_SHARE="${_DC_SELF_DIR}"
elif [ -n "${DC_SHARE:-}" ] && [ -f "${DC_SHARE}/distro-detect.sh" ]; then
    : # DC_SHARE da ambiente valido (AppRun)
elif [ -n "${APPDIR:-}" ] && [ -f "${APPDIR}/usr/share/distroClone/distro-detect.sh" ]; then
    DC_SHARE="${APPDIR}/usr/share/distroClone"
else
    DC_SHARE="/usr/share/distroClone"
fi
export DC_SHARE
echo "=========================================="
echo "    $MSG_BANNER_TITLE     "
echo "=========================================="

set -e
set -o pipefail
trap '' PIPE

# Function to find DC logo
# Priority: 1) APPDIR (AppImage) → 2) DC_SHARE (AppRun copy or .deb) → 3) system hicolor → 4) ImageMagick
get_dc_logo() {
    local SIZE="${1:-128}"
    for s in "$SIZE" 256 128 48; do
        # 1. Hicolor icons inside AppImage (APPDIR set by AppRun runtime)
        if [ -n "${APPDIR:-}" ] && [ -f "${APPDIR}/usr/share/icons/hicolor/${s}x${s}/apps/distroClone.png" ]; then
            echo "${APPDIR}/usr/share/icons/hicolor/${s}x${s}/apps/distroClone.png"
            return 0
        fi
        # 2. System hicolor icon (installed from .deb)
        local ICON="/usr/share/icons/hicolor/${s}x${s}/apps/distroClone.png"
        if [ -f "$ICON" ]; then
            echo "$ICON"
            return 0
        fi
    done
    # 3. DC_SHARE: distroClone-logo.png copied by AppRun (128x128 custom) or from .deb
    if [ -f "${DC_SHARE:-}/distroClone-logo.png" ]; then
        echo "${DC_SHARE}/distroClone-logo.png"
        return 0
    fi
    # 4. Temp cache (already generated in this session)
    local TMP="/tmp/distroClone-logo-${SIZE}.png"
    if [ -f "$TMP" ]; then
        echo "$TMP"
        return 0
    fi
    # 5. ImageMagick 7 uses 'magick', IM6 uses 'convert'
    local IM_CMD=""
    command -v magick >/dev/null 2>&1 && IM_CMD="magick"
    [ -z "$IM_CMD" ] && command -v convert >/dev/null 2>&1 && IM_CMD="convert"
    if [ -n "$IM_CMD" ]; then
        if [ "$SIZE" -eq 256 ]; then
            $IM_CMD -size 256x256 xc:transparent \
                -fill '#0d47a1' \
                -draw 'polygon 128,6 228,58 228,198 128,250 28,198 28,58' \
                -fill 'none' -strokewidth 5 -stroke '#1976d2' \
                -draw 'polygon 128,28 208,72 208,184 128,228 48,184 48,72' \
                -fill '#2196f3' \
                -draw 'polygon 128,58 184,88 184,168 128,198 72,168 72,88' \
                -fill 'white' -font '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' \
                -pointsize 56 -gravity center -annotate +0+0 'DC' \
                "$TMP" 2>/dev/null && echo "$TMP" && return 0
        else
            $IM_CMD -size 128x128 xc:transparent \
                -fill '#0d47a1' \
                -draw 'polygon 64,3 114,29 114,99 64,125 14,99 14,29' \
                -fill 'none' -strokewidth 3 -stroke '#1976d2' \
                -draw 'polygon 64,14 104,36 104,92 64,114 24,92 24,36' \
                -fill '#2196f3' \
                -draw 'polygon 64,29 92,44 92,84 64,99 36,84 36,44' \
                -fill 'white' -font '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' \
                -pointsize 28 -gravity center -annotate +0+0 'DC' \
                "$TMP" 2>/dev/null && echo "$TMP" && return 0
        fi
    fi
    echo ""
}

# ImageMagick command (global for the entire script)
IM_CMD=""
command -v magick >/dev/null 2>&1 && IM_CMD="magick"
[ -z "$IM_CMD" ] && command -v convert >/dev/null 2>&1 && IM_CMD="convert"

############################################
# MULTILANGUAGE SUPPORT
############################################
# Auto-detect language from system locale or --lang flag
# Supported: en (English, default), it (Italian), fr (French), es (Spanish), de (German), pt (Portuguese)
# Usage: distroClone --lang=it

DISTROCLONE_LANG="${DISTROCLONE_LANG:-}"

# Parse --lang flag from arguments
for arg in "$@"; do
    case "$arg" in
        --lang=*) DISTROCLONE_LANG="${arg#--lang=}" ;;
    esac
done

# Auto-detect from system locale if not specified
if [ -z "$DISTROCLONE_LANG" ]; then
    SYS_LANG="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
    case "$SYS_LANG" in
        it*) DISTROCLONE_LANG="it" ;;
        fr*) DISTROCLONE_LANG="fr" ;;
        es*) DISTROCLONE_LANG="es" ;;
        de*) DISTROCLONE_LANG="de" ;;
        pt*) DISTROCLONE_LANG="pt" ;;
        *)   DISTROCLONE_LANG="en" ;;
    esac
fi

load_lang_en() {
    # --- Startup ---
    MSG_BANNER_TITLE="🐧 DistroClone - Live ISO Builder"
    MSG_ERROR_OS_RELEASE="ERROR: /etc/os-release not found!"
    MSG_DETECTED_DISTRO="Detected distribution:"
    MSG_NAME="Name"
    MSG_VERSION="Version"
    MSG_DESKTOP="Desktop"
    MSG_ARCHITECTURE="Architecture"
    MSG_KERNEL="Kernel"

    # --- Splash ---
    MSG_SPLASH_TITLE="DistroClone"
    MSG_SPLASH_TEXT="\n<big><b>DistroClone - Live ISO Builder</b></big>\n\n<i>Initializing, please wait...\nInstalling required packages...</i>\n"

    # --- GUI detection ---
    MSG_STEP0="[0/28] Auto-detect Distro"
    MSG_STEP1="[1/30] GUI Tool Selection"
    MSG_GUI_SELECTED="✓ Graphical interface selected"
    MSG_STEP2="[2/30] GUI Question Wrapper"
    MSG_STEP3="[3/30] Welcome GUI"
    MSG_YAD_DETECTED="✓ YAD detected - advanced interface"
    MSG_ZENITY_DETECTED="✓ Zenity detected - standard interface"
    MSG_NO_GUI="No GUI available - terminal mode"

    # --- Question wrapper ---
    MSG_BTN_YES="Yes"
    MSG_BTN_NO="No"
    MSG_TTY_YN="y/N"
    MSG_TTY_PROCEED_YN="y/n"

    # --- Welcome dialog ---
    MSG_WELCOME_TITLE="DistroClone Universal ISO Builder v1.3.7"
    MSG_WELCOME_HEADING="Welcome to DistroClone"
    MSG_WELCOME_SUBTITLE="Universal Live ISO Builder for distro Debian-based"
    MSG_SYSTEM_DETECTED="System Detected"
    MSG_DISTRO="Distro"
    MSG_ISO_CREATED="ISO Created"
    MSG_ISO_GENERATED="ISO that will be generated"
    MSG_BUILD_CONFIG="$MSG_BUILD_CONFIG"
    MSG_FIELD_COMPRESSION="<b>Squashfs compression type</b>:"
    MSG_COMP_STANDARD="Standard xz (15-20 min)"
    MSG_COMP_FAST="Fast lz4 (5-10 min)"
    MSG_COMP_MAX="Maximum xz+bcj (25-35 min)"
    MSG_FIELD_PASSWORD="<b>Password live system</b> (user: ${_LIVEUSER_LABEL}):"
    MSG_FIELD_HOSTNAME="<b>Hostname live system</b>:"
    MSG_MIN_REQUIREMENTS="Minimum Requirements"
    MSG_MIN_REQ_TEXT="• Disk space: 4-6 GB free in /mnt\n• RAM: 2 GB minimum\n• Estimated time: 10-30 minutes (depends on the compression)"
    MSG_BTN_CANCEL="Cancel!gtk-cancel"
    MSG_BTN_NEXT="Next - Start Build!gtk-ok"
    MSG_BUILD_CANCELED="Build canceled by user"
    MSG_CHOSEN_CONFIG="✓ Chosen configuration:"
    MSG_COMPRESSION="Compression"
    MSG_PASSWORD_ROOT="Password root"
    MSG_DEFAULT_ROOT="default (root)"
    MSG_PERSONALIZED="personalized"
    MSG_DEFAULT_CONFIG="✓ Using default configurations"
    MSG_ZENITY_MODE="(Zenity mode)"
    MSG_PROCESS="Process"
    MSG_PROCESS_TEXT="[00-28] Cloning → Configuration → Squashfs → ISO"
    MSG_PRESS_OK="Press OK to start creating the live ISO..."
    MSG_PROCEED_BUILD="Proceed with the build?"
    MSG_BUILD_CANCELLED="Build cancelled"

    # --- TTY welcome ---
    MSG_TTY_UNIVERSAL="Universal"
    MSG_TTY_LIVEISOBUILDER="Live ISO Builder for Debian-based"
    MSG_TTY_DATE="Date"
    MSG_TTY_SYSTEM_DETECTED="SYSTEM DETECTED"
    MSG_TTY_ISO_GENERATED="ISO THAT WILL BE GENERATED"
    MSG_TTY_REQUIREMENTS="REQUIREMENTS"
    MSG_TTY_DISKSPACE="Disk space: 4-6 GB free in /mnt"
    MSG_TTY_RAM="RAM: 2 GB minimum"
    MSG_TTY_TIME="Estimated time: 10-30 minutes"

    # --- Build log ---
    MSG_BUILDLOG_TITLE="DistroClone - Build Log"
    MSG_BTN_HIDE="Close!gtk-close"

    # --- Steps ---
    MSG_STEP4="[4/30] Config"
    MSG_STEP5="[5/30] Cleanup mount"
    MSG_STEP6="[6/30] Mount directory"
    MSG_STEP7="[7/30][PRE] SOURCE & mount sanity check"
    MSG_ERR_SOURCE="ERROR: SOURCE must be / (found: \$SOURCE)"
    MSG_ERR_DEST_MOUNTED="ERROR: DEST is already mounted"
    MSG_ERR_LIVEDIR_MOUNTED="ERROR: LIVE_DIR is mounted (recursive clone risk)"
    MSG_WARN_MULTI_ROOT="WARNING: multiple root filesystems detected"
    MSG_STEP8="[8/30] System Clone rsync (this may take several minutes)..."
    MSG_FORCED_CLEAN_HOME="→ Forced cleaning /home on cloned system"
    MSG_STEP9="[9/30] Cleanup build-only tools"
    MSG_ERR_DEST_NOTSET="ERROR: DEST not set or not a directory, cleanup skipped"
    MSG_STEP10="[10/30] Bind mount chroot"
    MSG_STEP11="[11/30] Remove host user"
    MSG_STEP12="[12/30] Prep /boot for Calamares"
    MSG_STEP13="[13/30] Cleanup pre-build"
    MSG_STEP14="[14/30] Logo-config-user-/etc/skel"

    # --- User config dialog ---
    MSG_USERCONF_TITLE="DistroClone - User Configurations"
    MSG_USERCONF_HEADING="<b>Copy user configurations to /etc/skel?</b>"
    MSG_USERCONF_TEXT="This will allow new users created after installation\nto have the same settings (theme, icons, desktop layout).\n\n<b>What will be copied:</b>\n- Desktop configurations (theme, icons, wallpaper)\n- Panel and dock layout\n- Application preferences\n\n<b>What will NOT be copied:</b>\n- Password and credentials\n- Cache and temporary files\n- VirtualBox/Nextcloud configurations etc etc\n\n<i>Recommended if you want to distribute an ISO with preset configurations.</i>"
    MSG_TTY_COPY_CONFIG="Copy configurations?"
    MSG_USER_DETECTED="→ User detected"
    MSG_SKEL_COPIED="✓ Configurations copied to /etc/skel"
    MSG_SKEL_NEWUSERS="✓ New users will have the same settings"
    MSG_SKEL_NOTFOUND="✗ Could not find user's .config for"
    MSG_SKEL_CLEANING="→ Cleaning /etc/skel from host configurations"
    MSG_SKEL_KEEPING="✓ Keeping default"
    MSG_SKEL_DEFAULT="→ /etc/skel kept with default configurations only"

    # --- Branding ---
    MSG_STEP15="[15/30] Dynamic branding Calamares"
    MSG_LOGO_COPIED="✓ Logo DistroClone copied"
    MSG_LOGO_NOTFOUND="→ DistroClone logo not found, generate integrated Hexagon logo"
    MSG_LOGO_GENERATED="✓ Built-in Hexagon DistroClone logo generated"
    MSG_WELCOME_COPIED="✓ Welcome screen DistroClone copied"
    MSG_WELCOME_NOTFOUND="→ Welcome screen DistroClone not found, generating placeholder"
    MSG_BRANDING_DESC="→ Creating branding.desc"
    MSG_BRANDING_QML="→ Creating show.qml"
    MSG_BRANDING_DONE="✓ Branding configured in"
    MSG_INSTALLER_COPIED="✓ DistroClone installer icon copied"
    MSG_INSTALLER_NOTFOUND="→ Installer icon not found, built-in Hexagon logo"
    MSG_INSTALLER_GENERATED="✓ Built-in Hexagon installer icon generated"

    # --- Chroot ---
    MSG_STEP16="[16/30] Chroot Config"
    MSG_CHROOT_INSTALLING="→ Chroot: installing packages and configuring (this may take several minutes)..."
    MSG_CHROOT_DONE="✓ Chroot configuration completed"

    # --- Post install ---
    MSG_STEP17="[17/30] Hook post-install cleanup"
    MSG_STEP18="[18/30] Umount chroot"
    MSG_STEP19="[19/30] Sanity check /boot"
    MSG_ERR_MISSING="ERROR: Missing"
    MSG_STEP20="[20/30] Copy kernel/initrd"
    MSG_ERR_KERNEL="ERROR: Kernel or initrd not found!"

    # --- Manual edit ---
    MSG_STEP21="[21/30] Advanced manual modifications"
    MSG_MANEDIT_TITLE="DistroClone - Advanced Configurations"
    MSG_MANEDIT_HEADING="<b>Do you want to make manual changes into the filesystem before creating the squashfs?</b>"
    MSG_MANEDIT_TEXT="This option is for advanced users who want:\n- Add/remove packages into the chroot\n- Edit configuration file\n- Customize your system before compression"
    MSG_MANEDIT_PATH="Path chroot:"
    MSG_MANEDIT_SELECT="Select <b>No</b> to continue normally."
    MSG_MANEDIT_ZENITY="Do you want to make manual changes to the filesystem before squashfs?"
    MSG_BTN_EDIT="Yes, I want to edit"
    MSG_BTN_CONTINUE="No, continue"
    MSG_PAUSE_TITLE="PAUSE - MANUAL CHANGES ENABLED"
    MSG_PAUSE_AVAILABLE="The filesystem is available in:"
    MSG_PAUSE_CHROOT="To enter the chroot:"
    MSG_PAUSE_DONE="When you're done, press ENTER to continue."
    MSG_PAUSE_ENTER="Press ENTER to continue creating the squashfs..."
    MSG_PAUSE_SHOOTING="Shooting in progress..."

    # --- Compression selection ---
    MSG_STEP22="[22/30] SquashFS compression selection"
    MSG_COMP_SELECT_TITLE="SquashFS compression"
    MSG_COMP_SELECT_TEXT="Select the type of compression:"
    MSG_COMP_USING="Using"
    MSG_COMP_CODE="Code"
    MSG_COMP_DESCRIPTION="Description"
    MSG_COMP_FAST_DESC="Fast (lz4, larger ISO)"
    MSG_COMP_STD_DESC="Standard (xz balanced)"
    MSG_COMP_MAX_DESC="Maximum compression (xz -Xbcj x86)"
    MSG_TTY_SELECT_COMP="Select SquashFS compression:"
    MSG_TTY_COMP_FAST="Fast (lz4, 5-10 min)"
    MSG_TTY_COMP_STD="Standard (xz, 15-20 min) [default]"
    MSG_TTY_COMP_MAX="Maximum (xz+bcj, 25-35 min)"
    MSG_TTY_CHOICE="Choice (F/S/M)"
    MSG_COMP_FAST_LOG="→ Fast compression (lz4)"
    MSG_COMP_STD_LOG="→ Standard compression (xz)"
    MSG_COMP_MAX_LOG="→ Maximum compression (xz+bcj)"

    # --- Squashfs ---
    MSG_STEP23="[23/30] Creating filesystem.squashfs (this may take several minutes)..."
    MSG_SQUASH_SIZE="✓ Squashfs size"

    # --- GRUB ---
    MSG_STEP24="[24/30] GRUB configuration"
    MSG_GRUB_CUSTOM="✓ GRUB custom background copied (override)"
    MSG_GRUB_DEFAULT="✓ GRUB background default generated (dark black)"
    MSG_GRUB_NOCONVERT="⚠ convert not available - fallback black background"
    MSG_STEP25="[25/30] GRUB EFI binaries"

    # --- EFI/ISO ---
    MSG_STEP26="[26/30] Creating efiboot.img"
    MSG_STEP27="[27/30] Creating isolinux BIOS"
    MSG_STEP28="[28/30] Creating ISO bootable (this may take several minutes)..."
    MSG_WARN_BIGISO="Warning: Big ISO, possible problems on older BIOSes"

    # --- Final ---
    MSG_STEP29="[29/30] Iso check and md5sum-sha256sum (this may take several minutes)..."
    MSG_ISO_SUCCESS="✓ ISO COMPLETED SUCCESSFULLY!"
    MSG_FILE="File"
    MSG_SIZE="Size"
    MSG_MD5_GEN="MD5 and sha256 checksum generation"
    MSG_CREATED="Create"
    MSG_TEST_ISO="To test the ISO:"
    MSG_TEST_VBOX="VirtualBox: Create VM and mount"
    MSG_TEST_USB="USB: dd if="

    MSG_STEP30="[30/30] (Last Step) Host system cleanup"
    MSG_REMOVING_CALAMARES="→ Removing Calamares from the host system..."
    MSG_WARN_CALA_FAIL="Warning: Calamares removal failed"
    MSG_CALAMARES_REMOVED="✓ Calamares removed from host system"
    MSG_REMOVING_LIVEBOOT="→ Removing live-boot and others from the host system..."
    MSG_REMOVING_DIR="→ Removing directory..."

    # --- Final dialog ---
    MSG_COMPLETED_TITLE="DistroClone - Completed"
    MSG_ISO_SUCCESS_BIG="<big><b>✓ ISO created successfully!</b></big>"
    MSG_TEST_TEXT="<b>Test the ISO:</b>\n• VirtualBox: Create VM and mount the ISO\n• QEMU: qemu-system-x86_64 -enable-kvm -m 4096 -cdrom __ISO__ -boot d\n• USB: dd if="
    MSG_ISO_ERROR="✗ ERROR: ISO not created!"
    MSG_ERROR_TITLE="DistroClone - Error"
    MSG_ISO_FAIL_BIG="<big><b>✗ ISO creation failed!</b></big>\n\nCheck the terminal for details."

    # --- show.qml (Calamares slideshow) ---
    MSG_QML_INSTALLING="Installing your system..."
    MSG_QML_WAIT="Please wait while files are copied"
    MSG_QML_CONFIGURING="Configuring your system..."
    MSG_QML_SERVICES="Setting up users and system services"
    MSG_QML_ALMOST="Almost done!"
    MSG_QML_COMPLETE="Installation will complete shortly"

    # --- GRUB menu entries ---
    MSG_GRUB_TRY="Try or Install"
    MSG_GRUB_SAFE="Live (Safe Graphics)"
    MSG_GRUB_INSTALL="Install"
}

load_lang_it() {
    # --- Startup ---
    MSG_BANNER_TITLE="🐧 DistroClone - Creatore ISO Live"
    MSG_ERROR_OS_RELEASE="ERRORE: /etc/os-release non trovato!"
    MSG_DETECTED_DISTRO="Distribuzione rilevata:"
    MSG_NAME="Nome"
    MSG_VERSION="Versione"
    MSG_DESKTOP="Desktop"
    MSG_ARCHITECTURE="Architettura"
    MSG_KERNEL="Kernel"

    # --- Splash ---
    MSG_SPLASH_TITLE="DistroClone"
    MSG_SPLASH_TEXT="\n<big><b>DistroClone - Creatore ISO Live</b></big>\n\n<i>Inizializzazione in corso...\nInstallazione pacchetti necessari...</i>\n"

    # --- GUI detection ---
    MSG_STEP0="[0/28] Rilevamento automatico Distro"
    MSG_STEP1="[1/30] Selezione interfaccia grafica"
    MSG_GUI_SELECTED="✓ Interfaccia grafica selezionata"
    MSG_STEP2="[2/30] Wrapper domande GUI"
    MSG_STEP3="[3/30] Schermata di benvenuto"
    MSG_YAD_DETECTED="✓ YAD rilevato - interfaccia avanzata"
    MSG_ZENITY_DETECTED="✓ Zenity rilevato - interfaccia standard"
    MSG_NO_GUI="Nessuna GUI disponibile - modalità terminale"

    # --- Question wrapper ---
    MSG_BTN_YES="Sì"
    MSG_BTN_NO="No"
    MSG_TTY_YN="s/N"
    MSG_TTY_PROCEED_YN="s/n"

    # --- Welcome dialog ---
    MSG_WELCOME_TITLE="DistroClone Creatore Universale ISO v1.3.7"
    MSG_WELCOME_HEADING="Benvenuto in DistroClone"
    MSG_WELCOME_SUBTITLE="Creatore universale ISO Live per distribuzioni Debian-based"
    MSG_SYSTEM_DETECTED="Sistema Rilevato"
    MSG_DISTRO="Distro"
    MSG_ISO_CREATED="ISO Creata"
    MSG_ISO_GENERATED="ISO che verrà generata"
    MSG_BUILD_CONFIG="Configurazione del processo di build:"
    MSG_FIELD_COMPRESSION="<b>Tipo compressione Squashfs</b>:"
    MSG_COMP_STANDARD="Standard xz (15-20 min)"
    MSG_COMP_FAST="Veloce lz4 (5-10 min)"
    MSG_COMP_MAX="Massima xz+bcj (25-35 min)"
    MSG_FIELD_PASSWORD="<b>Password sistema live</b> (utente: ${_LIVEUSER_LABEL}):"
    MSG_FIELD_HOSTNAME="<b>Hostname sistema live</b>:"
    MSG_MIN_REQUIREMENTS="Requisiti Minimi"
    MSG_MIN_REQ_TEXT="• Spazio disco: 4-6 GB liberi in /mnt\n• RAM: 2 GB minimo\n• Tempo stimato: 10-30 minuti (dipende dalla compressione)"
    MSG_BTN_CANCEL="Annulla!gtk-cancel"
    MSG_BTN_NEXT="Avanti - Avvia Build!gtk-ok"
    MSG_BUILD_CANCELED="Build annullato dall'utente"
    MSG_CHOSEN_CONFIG="✓ Configurazione scelta:"
    MSG_COMPRESSION="Compressione"
    MSG_PASSWORD_ROOT="Password root"
    MSG_DEFAULT_ROOT="predefinita (root)"
    MSG_PERSONALIZED="personalizzata"
    MSG_DEFAULT_CONFIG="✓ Configurazioni predefinite in uso"
    MSG_ZENITY_MODE="(modalità Zenity)"
    MSG_PROCESS="Processo"
    MSG_PROCESS_TEXT="[00-28] Clonazione → Configurazione → Squashfs → ISO"
    MSG_PRESS_OK="Premi OK per avviare la creazione della ISO live..."
    MSG_PROCEED_BUILD="Procedere con il build?"
    MSG_BUILD_CANCELLED="Build annullato"

    # --- TTY welcome ---
    MSG_TTY_UNIVERSAL="Universale"
    MSG_TTY_LIVEISOBUILDER="Creatore ISO Live per Debian-based"
    MSG_TTY_DATE="Data"
    MSG_TTY_SYSTEM_DETECTED="SISTEMA RILEVATO"
    MSG_TTY_ISO_GENERATED="ISO CHE VERRÀ GENERATA"
    MSG_TTY_REQUIREMENTS="REQUISITI"
    MSG_TTY_DISKSPACE="Spazio disco: 4-6 GB liberi in /mnt"
    MSG_TTY_RAM="RAM: 2 GB minimo"
    MSG_TTY_TIME="Tempo stimato: 10-30 minuti"

    # --- Build log ---
    MSG_BUILDLOG_TITLE="DistroClone - Log di Build"
    MSG_BTN_HIDE="Chiudi!gtk-close"

    # --- Steps ---
    MSG_STEP4="[4/30] Configurazione"
    MSG_STEP5="[5/30] Pulizia mount"
    MSG_STEP6="[6/30] Directory di mount"
    MSG_STEP7="[7/30][PRE] Controllo sorgente e mount"
    MSG_ERR_SOURCE="ERRORE: SOURCE deve essere / (trovato: \$SOURCE)"
    MSG_ERR_DEST_MOUNTED="ERRORE: DEST è già montato"
    MSG_ERR_LIVEDIR_MOUNTED="ERRORE: LIVE_DIR è montato (rischio clone ricorsivo)"
    MSG_WARN_MULTI_ROOT="AVVISO: rilevati filesystem root multipli"
    MSG_STEP8="[8/30] Clonazione sistema rsync (potrebbe richiedere diversi minuti)..."
    MSG_FORCED_CLEAN_HOME="→ Pulizia forzata /home nel sistema clonato"
    MSG_STEP9="[9/30] Pulizia strumenti di build"
    MSG_ERR_DEST_NOTSET="ERRORE: DEST non impostato o non è una directory, pulizia saltata"
    MSG_STEP10="[10/30] Bind mount chroot"
    MSG_STEP11="[11/30] Rimozione utenti host"
    MSG_STEP12="[12/30] Preparazione /boot per Calamares"
    MSG_STEP13="[13/30] Pulizia pre-build"
    MSG_STEP14="[14/30] Logo-config-utente-/etc/skel"

    # --- User config dialog ---
    MSG_USERCONF_TITLE="DistroClone - Configurazioni Utente"
    MSG_USERCONF_HEADING="<b>Copiare le configurazioni utente in /etc/skel?</b>"
    MSG_USERCONF_TEXT="Questo permetterà ai nuovi utenti creati dopo l'installazione\ndi avere le stesse impostazioni (tema, icone, layout desktop).\n\n<b>Cosa verrà copiato:</b>\n- Configurazioni desktop (tema, icone, sfondo)\n- Layout pannello e dock\n- Preferenze applicazioni\n\n<b>Cosa NON verrà copiato:</b>\n- Password e credenziali\n- Cache e file temporanei\n- Configurazioni VirtualBox/Nextcloud ecc ecc\n\n<i>Consigliato se vuoi distribuire una ISO con configurazioni preimpostate.</i>"
    MSG_TTY_COPY_CONFIG="Copiare le configurazioni?"
    MSG_USER_DETECTED="→ Utente rilevato"
    MSG_SKEL_COPIED="✓ Configurazioni copiate in /etc/skel"
    MSG_SKEL_NEWUSERS="✓ I nuovi utenti avranno le stesse impostazioni"
    MSG_SKEL_NOTFOUND="✗ Impossibile trovare .config dell'utente"
    MSG_SKEL_CLEANING="→ Pulizia /etc/skel dalle configurazioni host"
    MSG_SKEL_KEEPING="✓ Mantenuto predefinito"
    MSG_SKEL_DEFAULT="→ /etc/skel mantenuto con configurazioni predefinite"

    # --- Branding ---
    MSG_STEP15="[15/30] Branding dinamico Calamares"
    MSG_LOGO_COPIED="✓ Logo DistroClone copiato"
    MSG_LOGO_NOTFOUND="→ Logo DistroClone non trovato, generazione logo esagonale integrato"
    MSG_LOGO_GENERATED="✓ Logo esagonale DistroClone integrato generato"
    MSG_WELCOME_COPIED="✓ Schermata di benvenuto DistroClone copiata"
    MSG_WELCOME_NOTFOUND="→ Schermata di benvenuto non trovata, generazione placeholder"
    MSG_BRANDING_DESC="→ Creazione branding.desc"
    MSG_BRANDING_QML="→ Creazione show.qml"
    MSG_BRANDING_DONE="✓ Branding configurato in"
    MSG_INSTALLER_COPIED="✓ Icona installer DistroClone copiata"
    MSG_INSTALLER_NOTFOUND="→ Icona installer non trovata, logo esagonale integrato"
    MSG_INSTALLER_GENERATED="✓ Icona esagonale installer generata"

    # --- Chroot ---
    MSG_STEP16="[16/30] Configurazione Chroot"
    MSG_CHROOT_INSTALLING="→ Chroot: installazione pacchetti e configurazione (potrebbe richiedere diversi minuti)..."
    MSG_CHROOT_DONE="✓ Configurazione chroot completata"

    # --- Post install ---
    MSG_STEP17="[17/30] Hook pulizia post-installazione"
    MSG_STEP18="[18/30] Umount chroot"
    MSG_STEP19="[19/30] Verifica /boot"
    MSG_ERR_MISSING="ERRORE: Mancante"
    MSG_STEP20="[20/30] Copia kernel/initrd"
    MSG_ERR_KERNEL="ERRORE: Kernel o initrd non trovati!"

    # --- Manual edit ---
    MSG_STEP21="[21/30] Modifiche manuali avanzate"
    MSG_MANEDIT_TITLE="DistroClone - Configurazioni Avanzate"
    MSG_MANEDIT_HEADING="<b>Vuoi apportare modifiche manuali al filesystem prima di creare lo squashfs?</b>"
    MSG_MANEDIT_TEXT="Questa opzione è per utenti avanzati che vogliono:\n- Aggiungere/rimuovere pacchetti nel chroot\n- Modificare file di configurazione\n- Personalizzare il sistema prima della compressione"
    MSG_MANEDIT_PATH="Percorso chroot:"
    MSG_MANEDIT_SELECT="Seleziona <b>No</b> per continuare normalmente."
    MSG_MANEDIT_ZENITY="Vuoi apportare modifiche manuali al filesystem prima dello squashfs?"
    MSG_BTN_EDIT="Sì, voglio modificare"
    MSG_BTN_CONTINUE="No, continua"
    MSG_PAUSE_TITLE="PAUSA - MODIFICHE MANUALI ABILITATE"
    MSG_PAUSE_AVAILABLE="Il filesystem è disponibile in:"
    MSG_PAUSE_CHROOT="Per entrare nel chroot:"
    MSG_PAUSE_DONE="Quando hai finito, premi INVIO per continuare."
    MSG_PAUSE_ENTER="Premi INVIO per continuare con la creazione dello squashfs..."
    MSG_PAUSE_SHOOTING="Creazione in corso..."

    # --- Compression selection ---
    MSG_STEP22="[22/30] Selezione compressione SquashFS"
    MSG_COMP_SELECT_TITLE="Compressione SquashFS"
    MSG_COMP_SELECT_TEXT="Seleziona il tipo di compressione:"
    MSG_COMP_USING="Usa"
    MSG_COMP_CODE="Codice"
    MSG_COMP_DESCRIPTION="Descrizione"
    MSG_COMP_FAST_DESC="Veloce (lz4, ISO più grande)"
    MSG_COMP_STD_DESC="Standard (xz bilanciato)"
    MSG_COMP_MAX_DESC="Compressione massima (xz -Xbcj x86)"
    MSG_TTY_SELECT_COMP="Seleziona compressione SquashFS:"
    MSG_TTY_COMP_FAST="Veloce (lz4, 5-10 min)"
    MSG_TTY_COMP_STD="Standard (xz, 15-20 min) [predefinito]"
    MSG_TTY_COMP_MAX="Massima (xz+bcj, 25-35 min)"
    MSG_TTY_CHOICE="Scelta (F/S/M)"
    MSG_COMP_FAST_LOG="→ Compressione veloce (lz4)"
    MSG_COMP_STD_LOG="→ Compressione standard (xz)"
    MSG_COMP_MAX_LOG="→ Compressione massima (xz+bcj)"

    # --- Squashfs ---
    MSG_STEP23="[23/30] Creazione filesystem.squashfs (potrebbe richiedere diversi minuti)..."
    MSG_SQUASH_SIZE="✓ Dimensione Squashfs"

    # --- GRUB ---
    MSG_STEP24="[24/30] Configurazione GRUB"
    MSG_GRUB_CUSTOM="✓ Sfondo GRUB personalizzato copiato (override)"
    MSG_GRUB_DEFAULT="✓ Sfondo GRUB predefinito generato (blu scuro)"
    MSG_GRUB_NOCONVERT="⚠ convert non disponibile - sfondo nero di fallback"
    MSG_STEP25="[25/30] Binari GRUB EFI"

    # --- EFI/ISO ---
    MSG_STEP26="[26/30] Creazione efiboot.img"
    MSG_STEP27="[27/30] Creazione isolinux BIOS"
    MSG_STEP28="[28/30] Creazione ISO avviabile (potrebbe richiedere diversi minuti)..."
    MSG_WARN_BIGISO="Avviso: ISO grande, possibili problemi su BIOS vecchi"

    # --- Final ---
    MSG_STEP29="[29/30] Verifica ISO e md5sum-sha256sum (potrebbe richiedere diversi minuti)..."
    MSG_ISO_SUCCESS="✓ ISO COMPLETATA CON SUCCESSO!"
    MSG_FILE="File"
    MSG_SIZE="Dimensione"
    MSG_MD5_GEN="Generazione checksum MD5 e sha256"
    MSG_CREATED="Creati"
    MSG_TEST_ISO="Per testare la ISO:"
    MSG_TEST_VBOX="VirtualBox: Crea una VM e monta"
    MSG_TEST_USB="USB: dd if="

    MSG_STEP30="[30/30] (Ultimo passo) Pulizia sistema host"
    MSG_REMOVING_CALAMARES="→ Rimozione Calamares dal sistema host..."
    MSG_WARN_CALA_FAIL="Avviso: Rimozione Calamares fallita"
    MSG_CALAMARES_REMOVED="✓ Calamares rimosso dal sistema host"
    MSG_REMOVING_LIVEBOOT="→ Rimozione live-boot e altri dal sistema host..."
    MSG_REMOVING_DIR="→ Rimozione directory..."

    # --- Final dialog ---
    MSG_COMPLETED_TITLE="DistroClone - Completato"
    MSG_ISO_SUCCESS_BIG="<big><b>✓ ISO creata con successo!</b></big>"
    MSG_TEST_TEXT="<b>Testa la ISO:</b>\n• VirtualBox: Crea una VM e monta la ISO\n• QEMU: qemu-system-x86_64 -enable-kvm -m 4096 -cdrom __ISO__ -boot d\n• USB: dd if="
    MSG_ISO_ERROR="✗ ERRORE: ISO non creata!"
    MSG_ERROR_TITLE="DistroClone - Errore"
    MSG_ISO_FAIL_BIG="<big><b>✗ Creazione ISO fallita!</b></big>\n\nControlla il terminale per i dettagli."

    # --- show.qml (Calamares slideshow) ---
    MSG_QML_INSTALLING="Installazione del sistema in corso..."
    MSG_QML_WAIT="Attendere la copia dei file"
    MSG_QML_CONFIGURING="Configurazione del sistema..."
    MSG_QML_SERVICES="Configurazione utenti e servizi di sistema"
    MSG_QML_ALMOST="Quasi fatto!"
    MSG_QML_COMPLETE="L'installazione verrà completata a breve"

    # --- GRUB menu entries ---
    MSG_GRUB_TRY="Prova o Installa"
    MSG_GRUB_SAFE="Live (Grafica Sicura)"
    MSG_GRUB_INSTALL="Installa"
}

load_lang_fr() {
    MSG_BANNER_TITLE="🐧 DistroClone - Créateur d'ISO Live"
    MSG_ERROR_OS_RELEASE="ERREUR : /etc/os-release introuvable !"
    MSG_DETECTED_DISTRO="Distribution détectée :"
    MSG_NAME="Nom"
    MSG_VERSION="Version"
    MSG_DESKTOP="Bureau"
    MSG_ARCHITECTURE="Architecture"
    MSG_KERNEL="Noyau"
    MSG_SPLASH_TITLE="DistroClone"
    MSG_SPLASH_TEXT="\n<big><b>DistroClone - Créateur d'ISO Live</b></big>\n\n<i>Initialisation en cours...\nInstallation des paquets requis...</i>\n"
    MSG_STEP0="[0/28] Détection automatique de la Distro"
    MSG_STEP1="[1/30] Sélection de l'interface graphique"
    MSG_GUI_SELECTED="✓ Interface graphique sélectionnée"
    MSG_STEP2="[2/30] Wrapper questions GUI"
    MSG_STEP3="[3/30] Écran d'accueil"
    MSG_YAD_DETECTED="✓ YAD détecté - interface avancée"
    MSG_ZENITY_DETECTED="✓ Zenity détecté - interface standard"
    MSG_NO_GUI="Aucune interface graphique disponible - mode terminal"
    MSG_BTN_YES="Oui"
    MSG_BTN_NO="Non"
    MSG_TTY_YN="o/N"
    MSG_TTY_PROCEED_YN="o/n"
    MSG_WELCOME_TITLE="DistroClone Créateur Universel d'ISO v1.3.7"
    MSG_WELCOME_HEADING="Bienvenue dans DistroClone"
    MSG_WELCOME_SUBTITLE="Créateur universel d'ISO Live pour distributions Debian"
    MSG_SYSTEM_DETECTED="Système Détecté"
    MSG_DISTRO="Distro"
    MSG_ISO_CREATED="ISO Créée"
    MSG_ISO_GENERATED="ISO qui sera générée"
    MSG_BUILD_CONFIG="Configuration du processus de build :"
    MSG_FIELD_COMPRESSION="<b>Type de compression Squashfs</b> :"
    MSG_COMP_STANDARD="Standard xz (15-20 min)"
    MSG_COMP_FAST="Rapide lz4 (5-10 min)"
    MSG_COMP_MAX="Maximale xz+bcj (25-35 min)"
    MSG_FIELD_PASSWORD="<b>Mot de passe root système live</b> (utilisateur live: admin/liveuser) :"
    MSG_FIELD_HOSTNAME="<b>Nom d'hôte système live</b> :"
    MSG_MIN_REQUIREMENTS="Configuration Minimale Requise"
    MSG_MIN_REQ_TEXT="• Espace disque : 4-6 Go libres dans /mnt\n• RAM : 2 Go minimum\n• Temps estimé : 10-30 minutes (selon la compression)"
    MSG_BTN_CANCEL="Annuler!gtk-cancel"
    MSG_BTN_NEXT="Suivant - Démarrer le Build!gtk-ok"
    MSG_BUILD_CANCELED="Build annulé par l'utilisateur"
    MSG_CHOSEN_CONFIG="✓ Configuration choisie :"
    MSG_COMPRESSION="Compression"
    MSG_PASSWORD_ROOT="Mot de passe root"
    MSG_DEFAULT_ROOT="par défaut (root)"
    MSG_PERSONALIZED="personnalisé"
    MSG_DEFAULT_CONFIG="✓ Configurations par défaut utilisées"
    MSG_ZENITY_MODE="(mode Zenity)"
    MSG_PROCESS="Processus"
    MSG_PROCESS_TEXT="[00-28] Clonage → Configuration → Squashfs → ISO"
    MSG_PRESS_OK="Appuyez sur OK pour démarrer la création de l'ISO live..."
    MSG_PROCEED_BUILD="Procéder au build ?"
    MSG_BUILD_CANCELLED="Build annulé"
    MSG_TTY_UNIVERSAL="Universel"
    MSG_TTY_LIVEISOBUILDER="Créateur ISO Live pour Debian-based"
    MSG_TTY_DATE="Date"
    MSG_TTY_SYSTEM_DETECTED="SYSTÈME DÉTECTÉ"
    MSG_TTY_ISO_GENERATED="ISO QUI SERA GÉNÉRÉE"
    MSG_TTY_REQUIREMENTS="CONFIGURATION REQUISE"
    MSG_TTY_DISKSPACE="Espace disque : 4-6 Go libres dans /mnt"
    MSG_TTY_RAM="RAM : 2 Go minimum"
    MSG_TTY_TIME="Temps estimé : 10-30 minutes"
    MSG_BUILDLOG_TITLE="DistroClone - Journal de Build"
    MSG_BTN_HIDE="Fermer!gtk-close"
    MSG_STEP4="[4/30] Configuration"
    MSG_STEP5="[5/30] Nettoyage montages"
    MSG_STEP6="[6/30] Répertoire de montage"
    MSG_STEP7="[7/30][PRÉ] Vérification source et montages"
    MSG_ERR_SOURCE="ERREUR : SOURCE doit être / (trouvé : \$SOURCE)"
    MSG_ERR_DEST_MOUNTED="ERREUR : DEST est déjà monté"
    MSG_ERR_LIVEDIR_MOUNTED="ERREUR : LIVE_DIR est monté (risque de clone récursif)"
    MSG_WARN_MULTI_ROOT="ATTENTION : systèmes de fichiers root multiples détectés"
    MSG_STEP8="[8/30] Clonage système rsync (cela peut prendre plusieurs minutes)..."
    MSG_FORCED_CLEAN_HOME="→ Nettoyage forcé de /home sur le système cloné"
    MSG_STEP9="[9/30] Nettoyage outils de build"
    MSG_ERR_DEST_NOTSET="ERREUR : DEST non défini ou n'est pas un répertoire, nettoyage ignoré"
    MSG_STEP10="[10/30] Montage bind chroot"
    MSG_STEP11="[11/30] Suppression utilisateurs hôte"
    MSG_STEP12="[12/30] Préparation /boot pour Calamares"
    MSG_STEP13="[13/30] Nettoyage pré-build"
    MSG_STEP14="[14/30] Logo-config-utilisateur-/etc/skel"
    MSG_USERCONF_TITLE="DistroClone - Configurations Utilisateur"
    MSG_USERCONF_HEADING="<b>Copier les configurations utilisateur dans /etc/skel ?</b>"
    MSG_USERCONF_TEXT="Cela permettra aux nouveaux utilisateurs créés après l'installation\nd'avoir les mêmes paramètres (thème, icônes, disposition du bureau).\n\n<b>Ce qui sera copié :</b>\n- Configurations du bureau (thème, icônes, fond d'écran)\n- Disposition du panneau et du dock\n- Préférences des applications\n\n<b>Ce qui ne sera PAS copié :</b>\n- Mots de passe et identifiants\n- Cache et fichiers temporaires\n- Configurations VirtualBox/Nextcloud etc.\n\n<i>Recommandé si vous souhaitez distribuer une ISO avec des configurations prédéfinies.</i>"
    MSG_TTY_COPY_CONFIG="Copier les configurations ?"
    MSG_USER_DETECTED="→ Utilisateur détecté"
    MSG_SKEL_COPIED="✓ Configurations copiées dans /etc/skel"
    MSG_SKEL_NEWUSERS="✓ Les nouveaux utilisateurs auront les mêmes paramètres"
    MSG_SKEL_NOTFOUND="✗ Impossible de trouver .config de l'utilisateur"
    MSG_SKEL_CLEANING="→ Nettoyage de /etc/skel des configurations hôte"
    MSG_SKEL_KEEPING="✓ Conservation du défaut"
    MSG_SKEL_DEFAULT="→ /etc/skel conservé avec les configurations par défaut uniquement"
    MSG_STEP15="[15/30] Branding dynamique Calamares"
    MSG_LOGO_COPIED="✓ Logo DistroClone copié"
    MSG_LOGO_NOTFOUND="→ Logo DistroClone non trouvé, génération du logo hexagonal intégré"
    MSG_LOGO_GENERATED="✓ Logo hexagonal DistroClone intégré généré"
    MSG_WELCOME_COPIED="✓ Écran d'accueil DistroClone copié"
    MSG_WELCOME_NOTFOUND="→ Écran d'accueil non trouvé, génération d'un placeholder"
    MSG_BRANDING_DESC="→ Création de branding.desc"
    MSG_BRANDING_QML="→ Création de show.qml"
    MSG_BRANDING_DONE="✓ Branding configuré dans"
    MSG_INSTALLER_COPIED="✓ Icône d'installation DistroClone copiée"
    MSG_INSTALLER_NOTFOUND="→ Icône d'installation non trouvée, logo hexagonal intégré"
    MSG_INSTALLER_GENERATED="✓ Icône hexagonale d'installation générée"
    MSG_STEP16="[16/30] Configuration Chroot"
    MSG_CHROOT_INSTALLING="→ Chroot : installation des paquets et configuration (cela peut prendre plusieurs minutes)..."
    MSG_CHROOT_DONE="✓ Configuration chroot terminée"
    MSG_STEP17="[17/30] Hook nettoyage post-installation"
    MSG_STEP18="[18/30] Démontage chroot"
    MSG_STEP19="[19/30] Vérification /boot"
    MSG_ERR_MISSING="ERREUR : Manquant"
    MSG_STEP20="[20/30] Copie kernel/initrd"
    MSG_ERR_KERNEL="ERREUR : Kernel ou initrd introuvable !"
    MSG_STEP21="[21/30] Modifications manuelles avancées"
    MSG_MANEDIT_TITLE="DistroClone - Configurations Avancées"
    MSG_MANEDIT_HEADING="<b>Voulez-vous apporter des modifications manuelles au système de fichiers avant de créer le squashfs ?</b>"
    MSG_MANEDIT_TEXT="Cette option est pour les utilisateurs avancés qui souhaitent :\n- Ajouter/supprimer des paquets dans le chroot\n- Modifier des fichiers de configuration\n- Personnaliser le système avant la compression"
    MSG_MANEDIT_PATH="Chemin chroot :"
    MSG_MANEDIT_SELECT="Sélectionnez <b>Non</b> pour continuer normalement."
    MSG_MANEDIT_ZENITY="Voulez-vous apporter des modifications manuelles au système de fichiers avant le squashfs ?"
    MSG_BTN_EDIT="Oui, je veux modifier"
    MSG_BTN_CONTINUE="Non, continuer"
    MSG_PAUSE_TITLE="PAUSE - MODIFICATIONS MANUELLES ACTIVÉES"
    MSG_PAUSE_AVAILABLE="Le système de fichiers est disponible dans :"
    MSG_PAUSE_CHROOT="Pour entrer dans le chroot :"
    MSG_PAUSE_DONE="Quand vous avez terminé, appuyez sur ENTRÉE pour continuer."
    MSG_PAUSE_ENTER="Appuyez sur ENTRÉE pour continuer la création du squashfs..."
    MSG_PAUSE_SHOOTING="Création en cours..."
    MSG_STEP22="[22/30] Sélection compression SquashFS"
    MSG_COMP_SELECT_TITLE="Compression SquashFS"
    MSG_COMP_SELECT_TEXT="Sélectionnez le type de compression :"
    MSG_COMP_USING="Utiliser"
    MSG_COMP_CODE="Code"
    MSG_COMP_DESCRIPTION="Description"
    MSG_COMP_FAST_DESC="Rapide (lz4, ISO plus grosse)"
    MSG_COMP_STD_DESC="Standard (xz équilibré)"
    MSG_COMP_MAX_DESC="Compression maximale (xz -Xbcj x86)"
    MSG_TTY_SELECT_COMP="Sélectionnez la compression SquashFS :"
    MSG_TTY_COMP_FAST="Rapide (lz4, 5-10 min)"
    MSG_TTY_COMP_STD="Standard (xz, 15-20 min) [défaut]"
    MSG_TTY_COMP_MAX="Maximale (xz+bcj, 25-35 min)"
    MSG_TTY_CHOICE="Choix (F/S/M)"
    MSG_COMP_FAST_LOG="→ Compression rapide (lz4)"
    MSG_COMP_STD_LOG="→ Compression standard (xz)"
    MSG_COMP_MAX_LOG="→ Compression maximale (xz+bcj)"
    MSG_STEP23="[23/30] Création filesystem.squashfs (cela peut prendre plusieurs minutes)..."
    MSG_SQUASH_SIZE="✓ Taille Squashfs"
    MSG_STEP24="[24/30] Configuration GRUB"
    MSG_GRUB_CUSTOM="✓ Fond GRUB personnalisé copié (override)"
    MSG_GRUB_DEFAULT="✓ Fond GRUB par défaut généré (bleu foncé)"
    MSG_GRUB_NOCONVERT="⚠ convert non disponible - fond noir de secours"
    MSG_STEP25="[25/30] Binaires GRUB EFI"
    MSG_STEP26="[26/30] Création efiboot.img"
    MSG_STEP27="[27/30] Création isolinux BIOS"
    MSG_STEP28="[28/30] Création ISO amorçable (cela peut prendre plusieurs minutes)..."
    MSG_WARN_BIGISO="Attention : ISO volumineuse, problèmes possibles sur anciens BIOS"
    MSG_STEP29="[29/30] Vérification ISO et md5sum-sha256sum (cela peut prendre plusieurs minutes)..."
    MSG_ISO_SUCCESS="✓ ISO COMPLÉTÉE AVEC SUCCÈS !"
    MSG_FILE="Fichier"
    MSG_SIZE="Taille"
    MSG_MD5_GEN="Génération des checksums MD5 et sha256"
    MSG_CREATED="Créés"
    MSG_TEST_ISO="Pour tester l'ISO :"
    MSG_TEST_VBOX="VirtualBox : Créer une VM et monter"
    MSG_TEST_USB="USB : dd if="
    MSG_STEP30="[30/30] (Dernière étape) Nettoyage système hôte"
    MSG_REMOVING_CALAMARES="→ Suppression de Calamares du système hôte..."
    MSG_WARN_CALA_FAIL="Attention : Suppression de Calamares échouée"
    MSG_CALAMARES_REMOVED="✓ Calamares supprimé du système hôte"
    MSG_REMOVING_LIVEBOOT="→ Suppression de live-boot et autres du système hôte..."
    MSG_REMOVING_DIR="→ Suppression du répertoire..."
    MSG_COMPLETED_TITLE="DistroClone - Terminé"
    MSG_ISO_SUCCESS_BIG="<big><b>✓ ISO créée avec succès !</b></big>"
    MSG_TEST_TEXT="<b>Tester l'ISO :</b>\n• VirtualBox : Créer une VM et monter l'ISO\n• QEMU : qemu-system-x86_64 -enable-kvm -m 4096 -cdrom __ISO__ -boot d\n• USB : dd if="
    MSG_ISO_ERROR="✗ ERREUR : ISO non créée !"
    MSG_ERROR_TITLE="DistroClone - Erreur"
    MSG_ISO_FAIL_BIG="<big><b>✗ Création de l'ISO échouée !</b></big>\n\nVérifiez le terminal pour les détails."
    MSG_QML_INSTALLING="Installation du système en cours..."
    MSG_QML_WAIT="Veuillez patienter pendant la copie des fichiers"
    MSG_QML_CONFIGURING="Configuration du système..."
    MSG_QML_SERVICES="Configuration des utilisateurs et services système"
    MSG_QML_ALMOST="Presque terminé !"
    MSG_QML_COMPLETE="L'installation se terminera bientôt"
    MSG_GRUB_TRY="Essayer ou Installer"
    MSG_GRUB_SAFE="Live (Graphiques Sécurisés)"
    MSG_GRUB_INSTALL="Installer"
}

load_lang_es() {
    MSG_BANNER_TITLE="🐧 DistroClone - Creador de ISO Live"
    MSG_ERROR_OS_RELEASE="ERROR: ¡/etc/os-release no encontrado!"
    MSG_DETECTED_DISTRO="Distribución detectada:"
    MSG_NAME="Nombre"
    MSG_VERSION="Versión"
    MSG_DESKTOP="Escritorio"
    MSG_ARCHITECTURE="Arquitectura"
    MSG_KERNEL="Kernel"
    MSG_SPLASH_TITLE="DistroClone"
    MSG_SPLASH_TEXT="\n<big><b>DistroClone - Creador de ISO Live</b></big>\n\n<i>Inicializando, por favor espere...\nInstalando paquetes necesarios...</i>\n"
    MSG_STEP0="[0/28] Detección automática de Distro"
    MSG_STEP1="[1/30] Selección de interfaz gráfica"
    MSG_GUI_SELECTED="✓ Interfaz gráfica seleccionada"
    MSG_STEP2="[2/30] Wrapper preguntas GUI"
    MSG_STEP3="[3/30] Pantalla de bienvenida"
    MSG_YAD_DETECTED="✓ YAD detectado - interfaz avanzada"
    MSG_ZENITY_DETECTED="✓ Zenity detectado - interfaz estándar"
    MSG_NO_GUI="Sin interfaz gráfica disponible - modo terminal"
    MSG_BTN_YES="Sí"
    MSG_BTN_NO="No"
    MSG_TTY_YN="s/N"
    MSG_TTY_PROCEED_YN="s/n"
    MSG_WELCOME_TITLE="DistroClone Creador Universal de ISO v1.3.7"
    MSG_WELCOME_HEADING="Bienvenido a DistroClone"
    MSG_WELCOME_SUBTITLE="Creador universal de ISO Live para distribuciones Debian"
    MSG_SYSTEM_DETECTED="Sistema Detectado"
    MSG_DISTRO="Distro"
    MSG_ISO_CREATED="ISO Creada"
    MSG_ISO_GENERATED="ISO que se generará"
    MSG_BUILD_CONFIG="Configuración del proceso de build:"
    MSG_FIELD_COMPRESSION="<b>Tipo de compresión Squashfs</b>:"
    MSG_COMP_STANDARD="Estándar xz (15-20 min)"
    MSG_COMP_FAST="Rápida lz4 (5-10 min)"
    MSG_COMP_MAX="Máxima xz+bcj (25-35 min)"
    MSG_FIELD_PASSWORD="<b>Contraseña root sistema live</b> (usuario live: admin/liveuser):"
    MSG_FIELD_HOSTNAME="<b>Nombre de host sistema live</b>:"
    MSG_MIN_REQUIREMENTS="Requisitos Mínimos"
    MSG_MIN_REQ_TEXT="• Espacio en disco: 4-6 GB libres en /mnt\n• RAM: 2 GB mínimo\n• Tiempo estimado: 10-30 minutos (depende de la compresión)"
    MSG_BTN_CANCEL="Cancelar!gtk-cancel"
    MSG_BTN_NEXT="Siguiente - Iniciar Build!gtk-ok"
    MSG_BUILD_CANCELED="Build cancelado por el usuario"
    MSG_CHOSEN_CONFIG="✓ Configuración elegida:"
    MSG_COMPRESSION="Compresión"
    MSG_PASSWORD_ROOT="Contraseña root"
    MSG_DEFAULT_ROOT="predeterminada (root)"
    MSG_PERSONALIZED="personalizada"
    MSG_DEFAULT_CONFIG="✓ Configuraciones predeterminadas en uso"
    MSG_ZENITY_MODE="(modo Zenity)"
    MSG_PROCESS="Proceso"
    MSG_PROCESS_TEXT="[00-28] Clonación → Configuración → Squashfs → ISO"
    MSG_PRESS_OK="Presione OK para iniciar la creación de la ISO live..."
    MSG_PROCEED_BUILD="¿Proceder con el build?"
    MSG_BUILD_CANCELLED="Build cancelado"
    MSG_TTY_UNIVERSAL="Universal"
    MSG_TTY_LIVEISOBUILDER="Creador ISO Live para Debian-based"
    MSG_TTY_DATE="Fecha"
    MSG_TTY_SYSTEM_DETECTED="SISTEMA DETECTADO"
    MSG_TTY_ISO_GENERATED="ISO QUE SE GENERARÁ"
    MSG_TTY_REQUIREMENTS="REQUISITOS"
    MSG_TTY_DISKSPACE="Espacio en disco: 4-6 GB libres en /mnt"
    MSG_TTY_RAM="RAM: 2 GB mínimo"
    MSG_TTY_TIME="Tiempo estimado: 10-30 minutos"
    MSG_BUILDLOG_TITLE="DistroClone - Registro de Build"
    MSG_BTN_HIDE="Cerrar!gtk-close"
    MSG_STEP4="[4/30] Configuración"
    MSG_STEP5="[5/30] Limpieza de montajes"
    MSG_STEP6="[6/30] Directorio de montaje"
    MSG_STEP7="[7/30][PRE] Verificación de origen y montajes"
    MSG_ERR_SOURCE="ERROR: SOURCE debe ser / (encontrado: \$SOURCE)"
    MSG_ERR_DEST_MOUNTED="ERROR: DEST ya está montado"
    MSG_ERR_LIVEDIR_MOUNTED="ERROR: LIVE_DIR está montado (riesgo de clonación recursiva)"
    MSG_WARN_MULTI_ROOT="ADVERTENCIA: múltiples sistemas de archivos root detectados"
    MSG_STEP8="[8/30] Clonación del sistema rsync (puede tardar varios minutos)..."
    MSG_FORCED_CLEAN_HOME="→ Limpieza forzada de /home en el sistema clonado"
    MSG_STEP9="[9/30] Limpieza de herramientas de build"
    MSG_ERR_DEST_NOTSET="ERROR: DEST no configurado o no es un directorio, limpieza omitida"
    MSG_STEP10="[10/30] Montaje bind chroot"
    MSG_STEP11="[11/30] Eliminación de usuarios del host"
    MSG_STEP12="[12/30] Preparación /boot para Calamares"
    MSG_STEP13="[13/30] Limpieza pre-build"
    MSG_STEP14="[14/30] Logo-config-usuario-/etc/skel"
    MSG_USERCONF_TITLE="DistroClone - Configuraciones de Usuario"
    MSG_USERCONF_HEADING="<b>¿Copiar configuraciones de usuario a /etc/skel?</b>"
    MSG_USERCONF_TEXT="Esto permitirá que los nuevos usuarios creados después de la instalación\ntengan las mismas configuraciones (tema, iconos, disposición del escritorio).\n\n<b>Lo que se copiará:</b>\n- Configuraciones del escritorio (tema, iconos, fondo)\n- Disposición del panel y dock\n- Preferencias de aplicaciones\n\n<b>Lo que NO se copiará:</b>\n- Contraseñas y credenciales\n- Caché y archivos temporales\n- Configuraciones de VirtualBox/Nextcloud etc.\n\n<i>Recomendado si desea distribuir una ISO con configuraciones preestablecidas.</i>"
    MSG_TTY_COPY_CONFIG="¿Copiar configuraciones?"
    MSG_USER_DETECTED="→ Usuario detectado"
    MSG_SKEL_COPIED="✓ Configuraciones copiadas a /etc/skel"
    MSG_SKEL_NEWUSERS="✓ Los nuevos usuarios tendrán las mismas configuraciones"
    MSG_SKEL_NOTFOUND="✗ No se pudo encontrar .config del usuario"
    MSG_SKEL_CLEANING="→ Limpieza de /etc/skel de configuraciones del host"
    MSG_SKEL_KEEPING="✓ Manteniendo predeterminado"
    MSG_SKEL_DEFAULT="→ /etc/skel mantenido solo con configuraciones predeterminadas"
    MSG_STEP15="[15/30] Branding dinámico Calamares"
    MSG_LOGO_COPIED="✓ Logo DistroClone copiado"
    MSG_LOGO_NOTFOUND="→ Logo DistroClone no encontrado, generando logo hexagonal integrado"
    MSG_LOGO_GENERATED="✓ Logo hexagonal DistroClone integrado generado"
    MSG_WELCOME_COPIED="✓ Pantalla de bienvenida DistroClone copiada"
    MSG_WELCOME_NOTFOUND="→ Pantalla de bienvenida no encontrada, generando placeholder"
    MSG_BRANDING_DESC="→ Creando branding.desc"
    MSG_BRANDING_QML="→ Creando show.qml"
    MSG_BRANDING_DONE="✓ Branding configurado en"
    MSG_INSTALLER_COPIED="✓ Icono del instalador DistroClone copiado"
    MSG_INSTALLER_NOTFOUND="→ Icono del instalador no encontrado, logo hexagonal integrado"
    MSG_INSTALLER_GENERATED="✓ Icono hexagonal del instalador generado"
    MSG_STEP16="[16/30] Configuración Chroot"
    MSG_CHROOT_INSTALLING="→ Chroot: instalando paquetes y configurando (puede tardar varios minutos)..."
    MSG_CHROOT_DONE="✓ Configuración chroot completada"
    MSG_STEP17="[17/30] Hook limpieza post-instalación"
    MSG_STEP18="[18/30] Desmontaje chroot"
    MSG_STEP19="[19/30] Verificación /boot"
    MSG_ERR_MISSING="ERROR: Faltante"
    MSG_STEP20="[20/30] Copiar kernel/initrd"
    MSG_ERR_KERNEL="ERROR: ¡Kernel o initrd no encontrados!"
    MSG_STEP21="[21/30] Modificaciones manuales avanzadas"
    MSG_MANEDIT_TITLE="DistroClone - Configuraciones Avanzadas"
    MSG_MANEDIT_HEADING="<b>¿Desea realizar cambios manuales en el sistema de archivos antes de crear el squashfs?</b>"
    MSG_MANEDIT_TEXT="Esta opción es para usuarios avanzados que desean:\n- Agregar/eliminar paquetes en el chroot\n- Editar archivos de configuración\n- Personalizar el sistema antes de la compresión"
    MSG_MANEDIT_PATH="Ruta chroot:"
    MSG_MANEDIT_SELECT="Seleccione <b>No</b> para continuar normalmente."
    MSG_MANEDIT_ZENITY="¿Desea realizar cambios manuales al sistema de archivos antes del squashfs?"
    MSG_BTN_EDIT="Sí, quiero editar"
    MSG_BTN_CONTINUE="No, continuar"
    MSG_PAUSE_TITLE="PAUSA - MODIFICACIONES MANUALES HABILITADAS"
    MSG_PAUSE_AVAILABLE="El sistema de archivos está disponible en:"
    MSG_PAUSE_CHROOT="Para entrar al chroot:"
    MSG_PAUSE_DONE="Cuando termine, presione ENTER para continuar."
    MSG_PAUSE_ENTER="Presione ENTER para continuar con la creación del squashfs..."
    MSG_PAUSE_SHOOTING="Creación en curso..."
    MSG_STEP22="[22/30] Selección de compresión SquashFS"
    MSG_COMP_SELECT_TITLE="Compresión SquashFS"
    MSG_COMP_SELECT_TEXT="Seleccione el tipo de compresión:"
    MSG_COMP_USING="Usar"
    MSG_COMP_CODE="Código"
    MSG_COMP_DESCRIPTION="Descripción"
    MSG_COMP_FAST_DESC="Rápida (lz4, ISO más grande)"
    MSG_COMP_STD_DESC="Estándar (xz equilibrado)"
    MSG_COMP_MAX_DESC="Compresión máxima (xz -Xbcj x86)"
    MSG_TTY_SELECT_COMP="Seleccione compresión SquashFS:"
    MSG_TTY_COMP_FAST="Rápida (lz4, 5-10 min)"
    MSG_TTY_COMP_STD="Estándar (xz, 15-20 min) [predeterminado]"
    MSG_TTY_COMP_MAX="Máxima (xz+bcj, 25-35 min)"
    MSG_TTY_CHOICE="Elección (F/S/M)"
    MSG_COMP_FAST_LOG="→ Compresión rápida (lz4)"
    MSG_COMP_STD_LOG="→ Compresión estándar (xz)"
    MSG_COMP_MAX_LOG="→ Compresión máxima (xz+bcj)"
    MSG_STEP23="[23/30] Creando filesystem.squashfs (puede tardar varios minutos)..."
    MSG_SQUASH_SIZE="✓ Tamaño Squashfs"
    MSG_STEP24="[24/30] Configuración GRUB"
    MSG_GRUB_CUSTOM="✓ Fondo GRUB personalizado copiado (override)"
    MSG_GRUB_DEFAULT="✓ Fondo GRUB predeterminado generado (azul oscuro)"
    MSG_GRUB_NOCONVERT="⚠ convert no disponible - fondo negro de respaldo"
    MSG_STEP25="[25/30] Binarios GRUB EFI"
    MSG_STEP26="[26/30] Creando efiboot.img"
    MSG_STEP27="[27/30] Creando isolinux BIOS"
    MSG_STEP28="[28/30] Creando ISO arrancable (puede tardar varios minutos)..."
    MSG_WARN_BIGISO="Advertencia: ISO grande, posibles problemas en BIOS antiguos"
    MSG_STEP29="[29/30] Verificación ISO y md5sum-sha256sum (puede tardar varios minutos)..."
    MSG_ISO_SUCCESS="✓ ¡ISO COMPLETADA CON ÉXITO!"
    MSG_FILE="Archivo"
    MSG_SIZE="Tamaño"
    MSG_MD5_GEN="Generación de checksums MD5 y sha256"
    MSG_CREATED="Creados"
    MSG_TEST_ISO="Para probar la ISO:"
    MSG_TEST_VBOX="VirtualBox: Crear VM y montar"
    MSG_TEST_USB="USB: dd if="
    MSG_STEP30="[30/30] (Último paso) Limpieza del sistema host"
    MSG_REMOVING_CALAMARES="→ Eliminando Calamares del sistema host..."
    MSG_WARN_CALA_FAIL="Advertencia: Eliminación de Calamares fallida"
    MSG_CALAMARES_REMOVED="✓ Calamares eliminado del sistema host"
    MSG_REMOVING_LIVEBOOT="→ Eliminando live-boot y otros del sistema host..."
    MSG_REMOVING_DIR="→ Eliminando directorio..."
    MSG_COMPLETED_TITLE="DistroClone - Completado"
    MSG_ISO_SUCCESS_BIG="<big><b>✓ ¡ISO creada con éxito!</b></big>"
    MSG_TEST_TEXT="<b>Probar la ISO:</b>\n• VirtualBox: Crear una VM y montar la ISO\n• QEMU: qemu-system-x86_64 -enable-kvm -m 4096 -cdrom __ISO__ -boot d\n• USB: dd if="
    MSG_ISO_ERROR="✗ ERROR: ¡ISO no creada!"
    MSG_ERROR_TITLE="DistroClone - Error"
    MSG_ISO_FAIL_BIG="<big><b>✗ ¡Creación de ISO fallida!</b></big>\n\nRevise el terminal para más detalles."
    MSG_QML_INSTALLING="Instalando el sistema..."
    MSG_QML_WAIT="Por favor espere mientras se copian los archivos"
    MSG_QML_CONFIGURING="Configurando el sistema..."
    MSG_QML_SERVICES="Configurando usuarios y servicios del sistema"
    MSG_QML_ALMOST="¡Casi listo!"
    MSG_QML_COMPLETE="La instalación se completará en breve"
    MSG_GRUB_TRY="Probar o Instalar"
    MSG_GRUB_SAFE="Live (Gráficos Seguros)"
    MSG_GRUB_INSTALL="Instalar"
}

load_lang_de() {
    MSG_BANNER_TITLE="🐧 DistroClone - Live-ISO-Ersteller"
    MSG_ERROR_OS_RELEASE="FEHLER: /etc/os-release nicht gefunden!"
    MSG_DETECTED_DISTRO="Erkannte Distribution:"
    MSG_NAME="Name"
    MSG_VERSION="Version"
    MSG_DESKTOP="Desktop"
    MSG_ARCHITECTURE="Architektur"
    MSG_KERNEL="Kernel"
    MSG_SPLASH_TITLE="DistroClone"
    MSG_SPLASH_TEXT="\n<big><b>DistroClone - Live-ISO-Ersteller</b></big>\n\n<i>Initialisierung läuft...\nErforderliche Pakete werden installiert...</i>\n"
    MSG_STEP0="[0/28] Automatische Distro-Erkennung"
    MSG_STEP1="[1/30] Auswahl der grafischen Oberfläche"
    MSG_GUI_SELECTED="✓ Grafische Oberfläche ausgewählt"
    MSG_STEP2="[2/30] GUI-Fragen-Wrapper"
    MSG_STEP3="[3/30] Willkommensbildschirm"
    MSG_YAD_DETECTED="✓ YAD erkannt - erweiterte Oberfläche"
    MSG_ZENITY_DETECTED="✓ Zenity erkannt - Standard-Oberfläche"
    MSG_NO_GUI="Keine grafische Oberfläche verfügbar - Terminalmodus"
    MSG_BTN_YES="Ja"
    MSG_BTN_NO="Nein"
    MSG_TTY_YN="j/N"
    MSG_TTY_PROCEED_YN="j/n"
    MSG_WELCOME_TITLE="DistroClone Universeller ISO-Ersteller v1.3.7"
    MSG_WELCOME_HEADING="Willkommen bei DistroClone"
    MSG_WELCOME_SUBTITLE="Universeller Live-ISO-Ersteller für Debian-basierte Distributionen"
    MSG_SYSTEM_DETECTED="Erkanntes System"
    MSG_DISTRO="Distro"
    MSG_ISO_CREATED="Erstellte ISO"
    MSG_ISO_GENERATED="ISO die erstellt wird"
    MSG_BUILD_CONFIG="Build-Prozesskonfiguration:"
    MSG_FIELD_COMPRESSION="<b>Squashfs-Komprimierungstyp</b>:"
    MSG_COMP_STANDARD="Standard xz (15-20 Min.)"
    MSG_COMP_FAST="Schnell lz4 (5-10 Min.)"
    MSG_COMP_MAX="Maximal xz+bcj (25-35 Min.)"
    MSG_FIELD_PASSWORD="<b>Root-Passwort Live-System</b> (Live-Benutzer: admin/liveuser):"
    MSG_FIELD_HOSTNAME="<b>Hostname Live-System</b>:"
    MSG_MIN_REQUIREMENTS="Mindestanforderungen"
    MSG_MIN_REQ_TEXT="• Festplattenspeicher: 4-6 GB frei in /mnt\n• RAM: mindestens 2 GB\n• Geschätzte Zeit: 10-30 Minuten (abhängig von der Komprimierung)"
    MSG_BTN_CANCEL="Abbrechen!gtk-cancel"
    MSG_BTN_NEXT="Weiter - Build starten!gtk-ok"
    MSG_BUILD_CANCELED="Build vom Benutzer abgebrochen"
    MSG_CHOSEN_CONFIG="✓ Gewählte Konfiguration:"
    MSG_COMPRESSION="Komprimierung"
    MSG_PASSWORD_ROOT="Root-Passwort"
    MSG_DEFAULT_ROOT="Standard (root)"
    MSG_PERSONALIZED="benutzerdefiniert"
    MSG_DEFAULT_CONFIG="✓ Standardkonfigurationen werden verwendet"
    MSG_ZENITY_MODE="(Zenity-Modus)"
    MSG_PROCESS="Prozess"
    MSG_PROCESS_TEXT="[00-28] Klonen → Konfiguration → Squashfs → ISO"
    MSG_PRESS_OK="Drücken Sie OK um die Erstellung der Live-ISO zu starten..."
    MSG_PROCEED_BUILD="Mit dem Build fortfahren?"
    MSG_BUILD_CANCELLED="Build abgebrochen"
    MSG_TTY_UNIVERSAL="Universal"
    MSG_TTY_LIVEISOBUILDER="Live-ISO-Ersteller für Debian-basiert"
    MSG_TTY_DATE="Datum"
    MSG_TTY_SYSTEM_DETECTED="ERKANNTES SYSTEM"
    MSG_TTY_ISO_GENERATED="ISO DIE ERSTELLT WIRD"
    MSG_TTY_REQUIREMENTS="ANFORDERUNGEN"
    MSG_TTY_DISKSPACE="Festplattenspeicher: 4-6 GB frei in /mnt"
    MSG_TTY_RAM="RAM: mindestens 2 GB"
    MSG_TTY_TIME="Geschätzte Zeit: 10-30 Minuten"
    MSG_BUILDLOG_TITLE="DistroClone - Build-Protokoll"
    MSG_BTN_HIDE="Schließen!gtk-close"
    MSG_STEP4="[4/30] Konfiguration"
    MSG_STEP5="[5/30] Mount-Bereinigung"
    MSG_STEP6="[6/30] Mount-Verzeichnis"
    MSG_STEP7="[7/30][PRE] Quell- und Mount-Prüfung"
    MSG_ERR_SOURCE="FEHLER: SOURCE muss / sein (gefunden: \$SOURCE)"
    MSG_ERR_DEST_MOUNTED="FEHLER: DEST ist bereits eingehängt"
    MSG_ERR_LIVEDIR_MOUNTED="FEHLER: LIVE_DIR ist eingehängt (Risiko eines rekursiven Klons)"
    MSG_WARN_MULTI_ROOT="WARNUNG: Mehrere Root-Dateisysteme erkannt"
    MSG_STEP8="[8/30] Systemklon rsync (kann mehrere Minuten dauern)..."
    MSG_FORCED_CLEAN_HOME="→ Erzwungene Bereinigung von /home im geklonten System"
    MSG_STEP9="[9/30] Bereinigung der Build-Tools"
    MSG_ERR_DEST_NOTSET="FEHLER: DEST nicht gesetzt oder kein Verzeichnis, Bereinigung übersprungen"
    MSG_STEP10="[10/30] Bind-Mount chroot"
    MSG_STEP11="[11/30] Host-Benutzer entfernen"
    MSG_STEP12="[12/30] Vorbereitung /boot für Calamares"
    MSG_STEP13="[13/30] Vor-Build-Bereinigung"
    MSG_STEP14="[14/30] Logo-Config-Benutzer-/etc/skel"
    MSG_USERCONF_TITLE="DistroClone - Benutzerkonfigurationen"
    MSG_USERCONF_HEADING="<b>Benutzerkonfigurationen nach /etc/skel kopieren?</b>"
    MSG_USERCONF_TEXT="Dies ermöglicht neuen Benutzern nach der Installation\ndie gleichen Einstellungen (Theme, Icons, Desktop-Layout).\n\n<b>Was kopiert wird:</b>\n- Desktop-Konfigurationen (Theme, Icons, Hintergrund)\n- Panel- und Dock-Layout\n- Anwendungseinstellungen\n\n<b>Was NICHT kopiert wird:</b>\n- Passwörter und Anmeldedaten\n- Cache und temporäre Dateien\n- VirtualBox/Nextcloud-Konfigurationen usw.\n\n<i>Empfohlen wenn Sie eine ISO mit voreingestellten Konfigurationen verteilen möchten.</i>"
    MSG_TTY_COPY_CONFIG="Konfigurationen kopieren?"
    MSG_USER_DETECTED="→ Benutzer erkannt"
    MSG_SKEL_COPIED="✓ Konfigurationen nach /etc/skel kopiert"
    MSG_SKEL_NEWUSERS="✓ Neue Benutzer haben die gleichen Einstellungen"
    MSG_SKEL_NOTFOUND="✗ Konnte .config des Benutzers nicht finden"
    MSG_SKEL_CLEANING="→ Bereinigung von /etc/skel von Host-Konfigurationen"
    MSG_SKEL_KEEPING="✓ Standard beibehalten"
    MSG_SKEL_DEFAULT="→ /etc/skel nur mit Standardkonfigurationen beibehalten"
    MSG_STEP15="[15/30] Dynamisches Calamares-Branding"
    MSG_LOGO_COPIED="✓ DistroClone-Logo kopiert"
    MSG_LOGO_NOTFOUND="→ DistroClone-Logo nicht gefunden, integriertes Hexagon-Logo wird generiert"
    MSG_LOGO_GENERATED="✓ Integriertes Hexagon-DistroClone-Logo generiert"
    MSG_WELCOME_COPIED="✓ DistroClone-Willkommensbildschirm kopiert"
    MSG_WELCOME_NOTFOUND="→ Willkommensbildschirm nicht gefunden, Platzhalter wird generiert"
    MSG_BRANDING_DESC="→ Erstelle branding.desc"
    MSG_BRANDING_QML="→ Erstelle show.qml"
    MSG_BRANDING_DONE="✓ Branding konfiguriert in"
    MSG_INSTALLER_COPIED="✓ DistroClone-Installationssymbol kopiert"
    MSG_INSTALLER_NOTFOUND="→ Installationssymbol nicht gefunden, integriertes Hexagon-Logo"
    MSG_INSTALLER_GENERATED="✓ Hexagonales Installationssymbol generiert"
    MSG_STEP16="[16/30] Chroot-Konfiguration"
    MSG_CHROOT_INSTALLING="→ Chroot: Pakete installieren und konfigurieren (kann mehrere Minuten dauern)..."
    MSG_CHROOT_DONE="✓ Chroot-Konfiguration abgeschlossen"
    MSG_STEP17="[17/30] Hook Nachinstallations-Bereinigung"
    MSG_STEP18="[18/30] Chroot aushängen"
    MSG_STEP19="[19/30] Überprüfung /boot"
    MSG_ERR_MISSING="FEHLER: Fehlt"
    MSG_STEP20="[20/30] Kernel/initrd kopieren"
    MSG_ERR_KERNEL="FEHLER: Kernel oder initrd nicht gefunden!"
    MSG_STEP21="[21/30] Erweiterte manuelle Änderungen"
    MSG_MANEDIT_TITLE="DistroClone - Erweiterte Konfigurationen"
    MSG_MANEDIT_HEADING="<b>Möchten Sie manuelle Änderungen am Dateisystem vornehmen bevor das Squashfs erstellt wird?</b>"
    MSG_MANEDIT_TEXT="Diese Option ist für fortgeschrittene Benutzer die:\n- Pakete im Chroot hinzufügen/entfernen möchten\n- Konfigurationsdateien bearbeiten möchten\n- Das System vor der Komprimierung anpassen möchten"
    MSG_MANEDIT_PATH="Chroot-Pfad:"
    MSG_MANEDIT_SELECT="Wählen Sie <b>Nein</b> um normal fortzufahren."
    MSG_MANEDIT_ZENITY="Möchten Sie manuelle Änderungen am Dateisystem vor dem Squashfs vornehmen?"
    MSG_BTN_EDIT="Ja, ich möchte bearbeiten"
    MSG_BTN_CONTINUE="Nein, weiter"
    MSG_PAUSE_TITLE="PAUSE - MANUELLE ÄNDERUNGEN AKTIVIERT"
    MSG_PAUSE_AVAILABLE="Das Dateisystem ist verfügbar in:"
    MSG_PAUSE_CHROOT="Um das Chroot zu betreten:"
    MSG_PAUSE_DONE="Wenn Sie fertig sind, drücken Sie ENTER um fortzufahren."
    MSG_PAUSE_ENTER="Drücken Sie ENTER um mit der Squashfs-Erstellung fortzufahren..."
    MSG_PAUSE_SHOOTING="Erstellung läuft..."
    MSG_STEP22="[22/30] SquashFS-Komprimierungsauswahl"
    MSG_COMP_SELECT_TITLE="SquashFS-Komprimierung"
    MSG_COMP_SELECT_TEXT="Wählen Sie den Komprimierungstyp:"
    MSG_COMP_USING="Verwenden"
    MSG_COMP_CODE="Code"
    MSG_COMP_DESCRIPTION="Beschreibung"
    MSG_COMP_FAST_DESC="Schnell (lz4, größere ISO)"
    MSG_COMP_STD_DESC="Standard (xz ausgewogen)"
    MSG_COMP_MAX_DESC="Maximale Komprimierung (xz -Xbcj x86)"
    MSG_TTY_SELECT_COMP="SquashFS-Komprimierung wählen:"
    MSG_TTY_COMP_FAST="Schnell (lz4, 5-10 Min.)"
    MSG_TTY_COMP_STD="Standard (xz, 15-20 Min.) [Standard]"
    MSG_TTY_COMP_MAX="Maximal (xz+bcj, 25-35 Min.)"
    MSG_TTY_CHOICE="Auswahl (F/S/M)"
    MSG_COMP_FAST_LOG="→ Schnelle Komprimierung (lz4)"
    MSG_COMP_STD_LOG="→ Standard-Komprimierung (xz)"
    MSG_COMP_MAX_LOG="→ Maximale Komprimierung (xz+bcj)"
    MSG_STEP23="[23/30] Erstelle filesystem.squashfs (kann mehrere Minuten dauern)..."
    MSG_SQUASH_SIZE="✓ Squashfs-Größe"
    MSG_STEP24="[24/30] GRUB-Konfiguration"
    MSG_GRUB_CUSTOM="✓ Benutzerdefinierter GRUB-Hintergrund kopiert (Override)"
    MSG_GRUB_DEFAULT="✓ Standard-GRUB-Hintergrund generiert (Dunkelblau)"
    MSG_GRUB_NOCONVERT="⚠ convert nicht verfügbar - schwarzer Fallback-Hintergrund"
    MSG_STEP25="[25/30] GRUB-EFI-Binärdateien"
    MSG_STEP26="[26/30] Erstelle efiboot.img"
    MSG_STEP27="[27/30] Erstelle isolinux BIOS"
    MSG_STEP28="[28/30] Erstelle bootfähige ISO (kann mehrere Minuten dauern)..."
    MSG_WARN_BIGISO="Warnung: Große ISO, mögliche Probleme auf älteren BIOS"
    MSG_STEP29="[29/30] ISO-Überprüfung und md5sum-sha256sum (kann mehrere Minuten dauern)..."
    MSG_ISO_SUCCESS="✓ ISO ERFOLGREICH ERSTELLT!"
    MSG_FILE="Datei"
    MSG_SIZE="Größe"
    MSG_MD5_GEN="MD5- und SHA256-Prüfsummen werden generiert"
    MSG_CREATED="Erstellt"
    MSG_TEST_ISO="Zum Testen der ISO:"
    MSG_TEST_VBOX="VirtualBox: VM erstellen und einbinden"
    MSG_TEST_USB="USB: dd if="
    MSG_STEP30="[30/30] (Letzter Schritt) Bereinigung des Host-Systems"
    MSG_REMOVING_CALAMARES="→ Entferne Calamares vom Host-System..."
    MSG_WARN_CALA_FAIL="Warnung: Entfernung von Calamares fehlgeschlagen"
    MSG_CALAMARES_REMOVED="✓ Calamares vom Host-System entfernt"
    MSG_REMOVING_LIVEBOOT="→ Entferne live-boot und andere vom Host-System..."
    MSG_REMOVING_DIR="→ Entferne Verzeichnis..."
    MSG_COMPLETED_TITLE="DistroClone - Abgeschlossen"
    MSG_ISO_SUCCESS_BIG="<big><b>✓ ISO erfolgreich erstellt!</b></big>"
    MSG_TEST_TEXT="<b>ISO testen:</b>\n• VirtualBox: VM erstellen und ISO einbinden\n• QEMU: qemu-system-x86_64 -enable-kvm -m 4096 -cdrom __ISO__ -boot d\n• USB: dd if="
    MSG_ISO_ERROR="✗ FEHLER: ISO nicht erstellt!"
    MSG_ERROR_TITLE="DistroClone - Fehler"
    MSG_ISO_FAIL_BIG="<big><b>✗ ISO-Erstellung fehlgeschlagen!</b></big>\n\nÜberprüfen Sie das Terminal für Details."
    MSG_QML_INSTALLING="System wird installiert..."
    MSG_QML_WAIT="Bitte warten während die Dateien kopiert werden"
    MSG_QML_CONFIGURING="System wird konfiguriert..."
    MSG_QML_SERVICES="Benutzer und Systemdienste werden eingerichtet"
    MSG_QML_ALMOST="Fast fertig!"
    MSG_QML_COMPLETE="Die Installation wird in Kürze abgeschlossen"
    MSG_GRUB_TRY="Testen oder Installieren"
    MSG_GRUB_SAFE="Live (Sichere Grafik)"
    MSG_GRUB_INSTALL="Installieren"
}

load_lang_pt() {
    MSG_BANNER_TITLE="🐧 DistroClone - Criador de ISO Live"
    MSG_ERROR_OS_RELEASE="ERRO: /etc/os-release não encontrado!"
    MSG_DETECTED_DISTRO="Distribuição detectada:"
    MSG_NAME="Nome"
    MSG_VERSION="Versão"
    MSG_DESKTOP="Ambiente de trabalho"
    MSG_ARCHITECTURE="Arquitetura"
    MSG_KERNEL="Kernel"
    MSG_SPLASH_TITLE="DistroClone"
    MSG_SPLASH_TEXT="\n<big><b>DistroClone - Criador de ISO Live</b></big>\n\n<i>Inicializando, por favor aguarde...\nInstalando pacotes necessários...</i>\n"
    MSG_STEP0="[0/28] Detecção automática da Distro"
    MSG_STEP1="[1/30] Seleção da interface gráfica"
    MSG_GUI_SELECTED="✓ Interface gráfica selecionada"
    MSG_STEP2="[2/30] Wrapper de perguntas GUI"
    MSG_STEP3="[3/30] Tela de boas-vindas"
    MSG_YAD_DETECTED="✓ YAD detectado - interface avançada"
    MSG_ZENITY_DETECTED="✓ Zenity detectado - interface padrão"
    MSG_NO_GUI="Nenhuma interface gráfica disponível - modo terminal"
    MSG_BTN_YES="Sim"
    MSG_BTN_NO="Não"
    MSG_TTY_YN="s/N"
    MSG_TTY_PROCEED_YN="s/n"
    MSG_WELCOME_TITLE="DistroClone Criador Universal de ISO v1.3.7"
    MSG_WELCOME_HEADING="Bem-vindo ao DistroClone"
    MSG_WELCOME_SUBTITLE="Criador universal de ISO Live para distribuições Debian"
    MSG_SYSTEM_DETECTED="Sistema Detectado"
    MSG_DISTRO="Distro"
    MSG_ISO_CREATED="ISO Criada"
    MSG_ISO_GENERATED="ISO que será gerada"
    MSG_BUILD_CONFIG="Configuração do processo de build:"
    MSG_FIELD_COMPRESSION="<b>Tipo de compressão Squashfs</b>:"
    MSG_COMP_STANDARD="Padrão xz (15-20 min)"
    MSG_COMP_FAST="Rápida lz4 (5-10 min)"
    MSG_COMP_MAX="Máxima xz+bcj (25-35 min)"
    MSG_FIELD_PASSWORD="<b>Senha root sistema live</b> (utilizador: admin/liveuser):"
    MSG_FIELD_HOSTNAME="<b>Hostname sistema live</b>:"
    MSG_MIN_REQUIREMENTS="Requisitos Mínimos"
    MSG_MIN_REQ_TEXT="• Espaço em disco: 4-6 GB livres em /mnt\n• RAM: 2 GB mínimo\n• Tempo estimado: 10-30 minutos (depende da compressão)"
    MSG_BTN_CANCEL="Cancelar!gtk-cancel"
    MSG_BTN_NEXT="Seguinte - Iniciar Build!gtk-ok"
    MSG_BUILD_CANCELED="Build cancelado pelo utilizador"
    MSG_CHOSEN_CONFIG="✓ Configuração escolhida:"
    MSG_COMPRESSION="Compressão"
    MSG_PASSWORD_ROOT="Senha root"
    MSG_DEFAULT_ROOT="padrão (root)"
    MSG_PERSONALIZED="personalizada"
    MSG_DEFAULT_CONFIG="✓ Configurações padrão em uso"
    MSG_ZENITY_MODE="(modo Zenity)"
    MSG_PROCESS="Processo"
    MSG_PROCESS_TEXT="[00-28] Clonagem → Configuração → Squashfs → ISO"
    MSG_PRESS_OK="Prima OK para iniciar a criação da ISO live..."
    MSG_PROCEED_BUILD="Prosseguir com o build?"
    MSG_BUILD_CANCELLED="Build cancelado"
    MSG_TTY_UNIVERSAL="Universal"
    MSG_TTY_LIVEISOBUILDER="Criador ISO Live para Debian-based"
    MSG_TTY_DATE="Data"
    MSG_TTY_SYSTEM_DETECTED="SISTEMA DETECTADO"
    MSG_TTY_ISO_GENERATED="ISO QUE SERÁ GERADA"
    MSG_TTY_REQUIREMENTS="REQUISITOS"
    MSG_TTY_DISKSPACE="Espaço em disco: 4-6 GB livres em /mnt"
    MSG_TTY_RAM="RAM: 2 GB mínimo"
    MSG_TTY_TIME="Tempo estimado: 10-30 minutos"
    MSG_BUILDLOG_TITLE="DistroClone - Registo de Build"
    MSG_BTN_HIDE="Fechar!gtk-close"
    MSG_STEP4="[4/30] Configuração"
    MSG_STEP5="[5/30] Limpeza de montagens"
    MSG_STEP6="[6/30] Diretório de montagem"
    MSG_STEP7="[7/30][PRÉ] Verificação de origem e montagens"
    MSG_ERR_SOURCE="ERRO: SOURCE deve ser / (encontrado: \$SOURCE)"
    MSG_ERR_DEST_MOUNTED="ERRO: DEST já está montado"
    MSG_ERR_LIVEDIR_MOUNTED="ERRO: LIVE_DIR está montado (risco de clone recursivo)"
    MSG_WARN_MULTI_ROOT="AVISO: múltiplos sistemas de ficheiros root detectados"
    MSG_STEP8="[8/30] Clonagem do sistema rsync (pode demorar vários minutos)..."
    MSG_FORCED_CLEAN_HOME="→ Limpeza forçada de /home no sistema clonado"
    MSG_STEP9="[9/30] Limpeza de ferramentas de build"
    MSG_ERR_DEST_NOTSET="ERRO: DEST não definido ou não é um diretório, limpeza ignorada"
    MSG_STEP10="[10/30] Montagem bind chroot"
    MSG_STEP11="[11/30] Remoção de utilizadores do host"
    MSG_STEP12="[12/30] Preparação /boot para Calamares"
    MSG_STEP13="[13/30] Limpeza pré-build"
    MSG_STEP14="[14/30] Logo-config-utilizador-/etc/skel"
    MSG_USERCONF_TITLE="DistroClone - Configurações do Utilizador"
    MSG_USERCONF_HEADING="<b>Copiar configurações do utilizador para /etc/skel?</b>"
    MSG_USERCONF_TEXT="Isto permitirá que novos utilizadores criados após a instalação\ntenham as mesmas definições (tema, ícones, disposição do ambiente de trabalho).\n\n<b>O que será copiado:</b>\n- Configurações do ambiente de trabalho (tema, ícones, fundo)\n- Disposição do painel e dock\n- Preferências de aplicações\n\n<b>O que NÃO será copiado:</b>\n- Palavras-passe e credenciais\n- Cache e ficheiros temporários\n- Configurações VirtualBox/Nextcloud etc.\n\n<i>Recomendado se pretende distribuir uma ISO com configurações predefinidas.</i>"
    MSG_TTY_COPY_CONFIG="Copiar configurações?"
    MSG_USER_DETECTED="→ Utilizador detectado"
    MSG_SKEL_COPIED="✓ Configurações copiadas para /etc/skel"
    MSG_SKEL_NEWUSERS="✓ Novos utilizadores terão as mesmas definições"
    MSG_SKEL_NOTFOUND="✗ Não foi possível encontrar .config do utilizador"
    MSG_SKEL_CLEANING="→ Limpeza de /etc/skel das configurações do host"
    MSG_SKEL_KEEPING="✓ Mantendo padrão"
    MSG_SKEL_DEFAULT="→ /etc/skel mantido apenas com configurações padrão"
    MSG_STEP15="[15/30] Branding dinâmico Calamares"
    MSG_LOGO_COPIED="✓ Logo DistroClone copiado"
    MSG_LOGO_NOTFOUND="→ Logo DistroClone não encontrado, a gerar logo hexagonal integrado"
    MSG_LOGO_GENERATED="✓ Logo hexagonal DistroClone integrado gerado"
    MSG_WELCOME_COPIED="✓ Ecrã de boas-vindas DistroClone copiado"
    MSG_WELCOME_NOTFOUND="→ Ecrã de boas-vindas não encontrado, a gerar placeholder"
    MSG_BRANDING_DESC="→ A criar branding.desc"
    MSG_BRANDING_QML="→ A criar show.qml"
    MSG_BRANDING_DONE="✓ Branding configurado em"
    MSG_INSTALLER_COPIED="✓ Ícone do instalador DistroClone copiado"
    MSG_INSTALLER_NOTFOUND="→ Ícone do instalador não encontrado, logo hexagonal integrado"
    MSG_INSTALLER_GENERATED="✓ Ícone hexagonal do instalador gerado"
    MSG_STEP16="[16/30] Configuração Chroot"
    MSG_CHROOT_INSTALLING="→ Chroot: a instalar pacotes e configurar (pode demorar vários minutos)..."
    MSG_CHROOT_DONE="✓ Configuração chroot concluída"
    MSG_STEP17="[17/30] Hook limpeza pós-instalação"
    MSG_STEP18="[18/30] Desmontar chroot"
    MSG_STEP19="[19/30] Verificação /boot"
    MSG_ERR_MISSING="ERRO: Em falta"
    MSG_STEP20="[20/30] Copiar kernel/initrd"
    MSG_ERR_KERNEL="ERRO: Kernel ou initrd não encontrados!"
    MSG_STEP21="[21/30] Modificações manuais avançadas"
    MSG_MANEDIT_TITLE="DistroClone - Configurações Avançadas"
    MSG_MANEDIT_HEADING="<b>Deseja efetuar alterações manuais no sistema de ficheiros antes de criar o squashfs?</b>"
    MSG_MANEDIT_TEXT="Esta opção é para utilizadores avançados que pretendem:\n- Adicionar/remover pacotes no chroot\n- Editar ficheiros de configuração\n- Personalizar o sistema antes da compressão"
    MSG_MANEDIT_PATH="Caminho chroot:"
    MSG_MANEDIT_SELECT="Selecione <b>Não</b> para continuar normalmente."
    MSG_MANEDIT_ZENITY="Deseja efetuar alterações manuais ao sistema de ficheiros antes do squashfs?"
    MSG_BTN_EDIT="Sim, quero editar"
    MSG_BTN_CONTINUE="Não, continuar"
    MSG_PAUSE_TITLE="PAUSA - MODIFICAÇÕES MANUAIS ATIVADAS"
    MSG_PAUSE_AVAILABLE="O sistema de ficheiros está disponível em:"
    MSG_PAUSE_CHROOT="Para entrar no chroot:"
    MSG_PAUSE_DONE="Quando terminar, prima ENTER para continuar."
    MSG_PAUSE_ENTER="Prima ENTER para continuar com a criação do squashfs..."
    MSG_PAUSE_SHOOTING="Criação em curso..."
    MSG_STEP22="[22/30] Seleção de compressão SquashFS"
    MSG_COMP_SELECT_TITLE="Compressão SquashFS"
    MSG_COMP_SELECT_TEXT="Selecione o tipo de compressão:"
    MSG_COMP_USING="Usar"
    MSG_COMP_CODE="Código"
    MSG_COMP_DESCRIPTION="Descrição"
    MSG_COMP_FAST_DESC="Rápida (lz4, ISO maior)"
    MSG_COMP_STD_DESC="Padrão (xz equilibrado)"
    MSG_COMP_MAX_DESC="Compressão máxima (xz -Xbcj x86)"
    MSG_TTY_SELECT_COMP="Selecione compressão SquashFS:"
    MSG_TTY_COMP_FAST="Rápida (lz4, 5-10 min)"
    MSG_TTY_COMP_STD="Padrão (xz, 15-20 min) [padrão]"
    MSG_TTY_COMP_MAX="Máxima (xz+bcj, 25-35 min)"
    MSG_TTY_CHOICE="Escolha (F/S/M)"
    MSG_COMP_FAST_LOG="→ Compressão rápida (lz4)"
    MSG_COMP_STD_LOG="→ Compressão padrão (xz)"
    MSG_COMP_MAX_LOG="→ Compressão máxima (xz+bcj)"
    MSG_STEP23="[23/30] A criar filesystem.squashfs (pode demorar vários minutos)..."
    MSG_SQUASH_SIZE="✓ Tamanho Squashfs"
    MSG_STEP24="[24/30] Configuração GRUB"
    MSG_GRUB_CUSTOM="✓ Fundo GRUB personalizado copiado (override)"
    MSG_GRUB_DEFAULT="✓ Fundo GRUB padrão gerado (azul escuro)"
    MSG_GRUB_NOCONVERT="⚠ convert não disponível - fundo preto de reserva"
    MSG_STEP25="[25/30] Binários GRUB EFI"
    MSG_STEP26="[26/30] A criar efiboot.img"
    MSG_STEP27="[27/30] A criar isolinux BIOS"
    MSG_STEP28="[28/30] A criar ISO arrancável (pode demorar vários minutos)..."
    MSG_WARN_BIGISO="Aviso: ISO grande, possíveis problemas em BIOS antigos"
    MSG_STEP29="[29/30] Verificação ISO e md5sum-sha256sum (pode demorar vários minutos)..."
    MSG_ISO_SUCCESS="✓ ISO CONCLUÍDA COM SUCESSO!"
    MSG_FILE="Ficheiro"
    MSG_SIZE="Tamanho"
    MSG_MD5_GEN="Geração de checksums MD5 e sha256"
    MSG_CREATED="Criados"
    MSG_TEST_ISO="Para testar a ISO:"
    MSG_TEST_VBOX="VirtualBox: Criar VM e montar"
    MSG_TEST_USB="USB: dd if="
    MSG_STEP30="[30/30] (Último passo) Limpeza do sistema host"
    MSG_REMOVING_CALAMARES="→ A remover Calamares do sistema host..."
    MSG_WARN_CALA_FAIL="Aviso: Remoção do Calamares falhou"
    MSG_CALAMARES_REMOVED="✓ Calamares removido do sistema host"
    MSG_REMOVING_LIVEBOOT="→ A remover live-boot e outros do sistema host..."
    MSG_REMOVING_DIR="→ A remover diretório..."
    MSG_COMPLETED_TITLE="DistroClone - Concluído"
    MSG_ISO_SUCCESS_BIG="<big><b>✓ ISO criada com sucesso!</b></big>"
    MSG_TEST_TEXT="<b>Testar a ISO:</b>\n• VirtualBox: Criar uma VM e montar a ISO\n• QEMU: qemu-system-x86_64 -enable-kvm -m 4096 -cdrom __ISO__ -boot d\n• USB: dd if="
    MSG_ISO_ERROR="✗ ERRO: ISO não criada!"
    MSG_ERROR_TITLE="DistroClone - Erro"
    MSG_ISO_FAIL_BIG="<big><b>✗ Criação da ISO falhou!</b></big>\n\nVerifique o terminal para detalhes."
    MSG_QML_INSTALLING="A instalar o sistema..."
    MSG_QML_WAIT="Por favor aguarde enquanto os ficheiros são copiados"
    MSG_QML_CONFIGURING="A configurar o sistema..."
    MSG_QML_SERVICES="A configurar utilizadores e serviços do sistema"
    MSG_QML_ALMOST="Quase pronto!"
    MSG_QML_COMPLETE="A instalação será concluída em breve"
    MSG_GRUB_TRY="Experimentar ou Instalar"
    MSG_GRUB_SAFE="Live (Gráficos Seguros)"
    MSG_GRUB_INSTALL="Instalar"
}

# Live user label for YAD — must be defined BEFORE load_lang_*
# because MSG_FIELD_PASSWORD uses it via ${_LIVEUSER_LABEL}
case "${DC_FAMILY:-arch}" in
    fedora)   _LIVEUSER_LABEL="liveuser" ;;
    arch)     _LIVEUSER_LABEL="archie"   ;;
    opensuse) _LIVEUSER_LABEL="linux"    ;;
    *)        _LIVEUSER_LABEL="admin"    ;;
esac

# Load selected language
case "$DISTROCLONE_LANG" in
    it) load_lang_it ;;
    fr) load_lang_fr ;;
    es) load_lang_es ;;
    de) load_lang_de ;;
    pt) load_lang_pt ;;
    *)  load_lang_en ;;
esac

echo "  Language: $DISTROCLONE_LANG"


############################################
# [0/28] AUTO-DETECT DISTRO
############################################
echo "$MSG_STEP0"

if [ ! -f /etc/os-release ]; then
    echo "$MSG_ERROR_OS_RELEASE"
    exit 1
fi

source /etc/os-release

# Dynamic variables from the distribution
DISTRO_NAME="${NAME}"
# Capitalize first letter (ubuntu -> Ubuntu, debian -> Debian)
DISTRO_NAME="$(echo "$DISTRO_NAME" | sed 's/^./\U&/')"
DISTRO_ID="${ID}"
DISTRO_VERSION="${VERSION_ID:-${BUILD_ID:-rolling}}"
DISTRO_PRETTY="${PRETTY_NAME}"

# Desktop environment detection
# pkexec/sudo clearano l'environment: recupera le variabili dalla sessione utente reale.
# Metodo: legge /proc/<pid>/environ dei processi dell'utente (funziona su X11 e Wayland).
# Recupera: XDG_CURRENT_DESKTOP, DISPLAY, WAYLAND_DISPLAY, XAUTHORITY, XDG_RUNTIME_DIR.
_DC_RECOVER_ENV() {
    local _u="$1"
    local _uid
    _uid=$(id -u "$_u" 2>/dev/null) || return 1
    local _pid _env
    for _pid in $(pgrep -u "$_uid" 2>/dev/null | head -20); do
        _env=$(tr '\0' '\n' < "/proc/${_pid}/environ" 2>/dev/null) || continue
        [ -z "$XDG_CURRENT_DESKTOP" ] && \
            XDG_CURRENT_DESKTOP=$(echo "$_env" | grep '^XDG_CURRENT_DESKTOP=' | cut -d= -f2- | head -1)
        [ -z "$DISPLAY" ] && \
            DISPLAY=$(echo "$_env" | grep '^DISPLAY=' | cut -d= -f2- | head -1)
        [ -z "$WAYLAND_DISPLAY" ] && \
            WAYLAND_DISPLAY=$(echo "$_env" | grep '^WAYLAND_DISPLAY=' | cut -d= -f2- | head -1)
        [ -z "$XAUTHORITY" ] && \
            XAUTHORITY=$(echo "$_env" | grep '^XAUTHORITY=' | cut -d= -f2- | head -1)
        [ -z "$XDG_RUNTIME_DIR" ] && \
            XDG_RUNTIME_DIR=$(echo "$_env" | grep '^XDG_RUNTIME_DIR=' | cut -d= -f2- | head -1)
        # Esci appena abbiamo almeno un display
        [ -n "${DISPLAY}${WAYLAND_DISPLAY}" ] && break
    done
    [ -n "$DISPLAY" ]          && export DISPLAY
    [ -n "$WAYLAND_DISPLAY" ]  && export WAYLAND_DISPLAY
    [ -n "$XAUTHORITY" ]       && export XAUTHORITY
    [ -n "$XDG_RUNTIME_DIR" ]  && export XDG_RUNTIME_DIR
    [ -n "$XDG_CURRENT_DESKTOP" ] && export XDG_CURRENT_DESKTOP
}

if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] || [ -z "$XDG_CURRENT_DESKTOP" ]; then
    # sudo: SUDO_USER contiene l'utente reale
    if [ -n "$SUDO_USER" ]; then
        _DC_RECOVER_ENV "$SUDO_USER" || true
    fi
    # pkexec: PKEXEC_UID contiene l'UID dell'utente reale
    if [ -n "$PKEXEC_UID" ] && { [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] || [ -z "$XDG_CURRENT_DESKTOP" ]; }; then
        PKEXEC_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
        [ -n "$PKEXEC_USER" ] && _DC_RECOVER_ENV "$PKEXEC_USER" || true
    fi
fi
unset -f _DC_RECOVER_ENV

if [ -n "$XDG_CURRENT_DESKTOP" ]; then
    DESKTOP_ENV="$XDG_CURRENT_DESKTOP"
elif pgrep -x "io.elementary.wingpanel" >/dev/null 2>&1 || pgrep -x "gala" >/dev/null 2>&1; then
    DESKTOP_ENV="Pantheon"
elif pgrep -x "mate-panel" >/dev/null 2>&1; then
    DESKTOP_ENV="MATE"
elif pgrep -x "gnome-shell" >/dev/null 2>&1; then
    DESKTOP_ENV="GNOME"
elif pgrep -x "cinnamon" >/dev/null 2>&1; then
    DESKTOP_ENV="Cinnamon"
elif pgrep -x "plasmashell" >/dev/null 2>&1; then
    DESKTOP_ENV="KDE"
elif pgrep -x "xfce4-panel" >/dev/null 2>&1; then
    DESKTOP_ENV="XFCE"
else
    DESKTOP_ENV="Unknown"
fi

# Correct capitalization for ISO name (e.g.: ubuntu -> Ubuntu, linuxmint -> LinuxMint)
DISTRO_ID_CAPITALIZED=$(echo "${DISTRO_ID}" | sed -e 's/\b\(.\)/\u\1/g' -e 's/linux/Linux/g' -e 's/mint/Mint/g')
DESKTOP_CAPITALIZED=$(echo "$DESKTOP_ENV" | sed -e 's/\b\(.\)/\u\1/g')

ISO_NAME="${DISTRO_ID_CAPITALIZED}-${DISTRO_VERSION}-${DESKTOP_CAPITALIZED}.iso"
# ISO9660 volume labels must be uppercase for compatibility with blkid/archiso
ISO_LABEL=$(echo "${DISTRO_ID}-Live" | tr '[:lower:]' '[:upper:]' | tr '-' '_')

echo ""
echo "$MSG_DETECTED_DISTRO"
echo "  $MSG_NAME: $DISTRO_NAME"
echo "  ID: $DISTRO_ID (ISO: $DISTRO_ID_CAPITALIZED)"
echo "  $MSG_VERSION: $DISTRO_VERSION"
echo "  $MSG_DESKTOP: $DESKTOP_ENV (ISO: $DESKTOP_CAPITALIZED)"
echo ""

############################################
# SPLASH SCREEN
############################################
SPLASH_PID="${DISTROCLONE_SPLASH_PID:-}"
LOG_PID=""
DC_LOG_FILE="/tmp/distroclone-build-$$.log"

# Centralized cleanup: closes log fd, kills SPLASH and LOG yad windows.
close_yad_windows() {
    # 1. Close fd 3 (flush log file)
    exec 3>&- 2>/dev/null || true

    # 2. SPLASH: direct kill (uses internal timeout)
    if [ -n "${SPLASH_PID:-}" ] && kill -0 "$SPLASH_PID" 2>/dev/null; then
        kill "$SPLASH_PID" 2>/dev/null || true
        wait "$SPLASH_PID" 2>/dev/null || true
    fi

    # 3. LOG window: kill + wait
    if [ -n "${LOG_PID:-}" ] && kill -0 "$LOG_PID" 2>/dev/null; then
        kill "$LOG_PID" 2>/dev/null || true
        wait "$LOG_PID" 2>/dev/null || true
    fi

    pkill -P $$ yad 2>/dev/null || true
    SPLASH_PID=""
    LOG_PID=""

    # Fix 50: remove host pacman cache — safe if already removed in step 30 (idempotent)
    rm -rf /mnt/.distroclone-pacman-cache 2>/dev/null || true
}
trap 'close_yad_windows' EXIT INT TERM

# If not launched from the .deb launcher, create splash if yad is already available
if [ "${DISTROCLONE_DISABLE_SPLASH:-0}" != "1" ] && \
   [ -z "$SPLASH_PID" ] && command -v yad >/dev/null 2>&1; then
    SPLASH_LOGO="$(get_dc_logo 256)"

    yad --info \
        --no-buttons \
        --timeout=20 \
        --title="$MSG_SPLASH_TITLE" \
        --text="$MSG_SPLASH_TEXT" \
        ${SPLASH_LOGO:+--window-icon="$SPLASH_LOGO"} \
        ${SPLASH_LOGO:+--image="$SPLASH_LOGO"} \
        --width=450 --height=280 \
        --center \
        --undecorated \
        --on-top \
        2>/dev/null &
    SPLASH_PID=$!
fi

############################################
# CROSS-DISTRO DEPENDENCY MANAGER
# Inspired by penguins-eggs (Piero Proietti, MIT)
# Replaces hardcoded apt block — supports:
#   Debian/Ubuntu, Arch, Fedora, openSUSE, Alpine
############################################

# Search for distro-detect.sh: first in DC_SHARE, then in the same dir as DistroClone.sh
DC_DETECT_LIB="${DC_SHARE}/distro-detect.sh"
_SELF_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
[ ! -f "$DC_DETECT_LIB" ] && DC_DETECT_LIB="${_SELF_DIR}/distro-detect.sh"
[ ! -f "$DC_DETECT_LIB" ] && DC_DETECT_LIB="/usr/share/distroClone/distro-detect.sh"

if [ -f "$DC_DETECT_LIB" ]; then
    # shellcheck source=/dev/null
    source "$DC_DETECT_LIB"
    dc_bootstrap
else
    # Inline fallback: detection from /etc/os-release without external dependencies
    echo "[WARN] distro-detect.sh not found — inline detection from /etc/os-release"
    _ID="$(. /etc/os-release 2>/dev/null && echo "${ID:-linux}")"
    _ID_LIKE="$(. /etc/os-release 2>/dev/null && echo "${ID_LIKE:-}")"
    _DETECT="${_ID} ${_ID_LIKE}"
    case "$_DETECT" in
        *fedora*|*rhel*|*centos*|*rocky*|*alma*)
            DC_FAMILY="fedora"; DC_PKG_MANAGER="dnf"; DC_PKG_INSTALL="dnf install -y"
            dnf install -y mtools zenity rsync xorriso imagemagick \
              grub2-efi-x64 grub2-pc-modules calamares yad fdisk \
              cryptsetup dracut 2>/dev/null || true
            ;;
        *arch*|*manjaro*|*endeavour*)
            DC_FAMILY="arch"; DC_PKG_MANAGER="pacman"; DC_PKG_INSTALL="pacman -S --noconfirm"
            pacman -Sy --noconfirm mtools zenity rsync libisoburn \
              imagemagick grub calamares yad cryptsetup util-linux 2>/dev/null || true
            ;;
        *)
            echo "[ERROR] Distro non supportata: $_ID — cross-distro AppImage supporta solo Arch e Fedora"
            exit 1
            ;;
    esac
    export DC_FAMILY DC_PKG_MANAGER DC_PKG_INSTALL
fi

# ── Arch feature detection ───────────────────────────────────────────────────
# DC_INITRAMFS / DC_KERNEL_FLAVOR / DC_LIVE_STACK set by dc_detect_arch_features()
# (called inside dc_bootstrap). Safe defaults for non-arch families.
DC_INITRAMFS="${DC_INITRAMFS:-}"
DC_KERNEL_FLAVOR="${DC_KERNEL_FLAVOR:-}"
DC_LIVE_STACK="${DC_LIVE_STACK:-}"
if [ "${DC_FAMILY:-}" = "arch" ]; then
    echo "[DC] Initramfs:    ${DC_INITRAMFS:-mkinitcpio}"
    echo "[DC] Kernel flavor: ${DC_KERNEL_FLAVOR:-generic}"
    echo "[DC] Live stack:   ${DC_LIVE_STACK:-archiso}"
fi

# DC_FAMILY is now known: update _LIVEUSER_LABEL and reload language messages
# (load_lang_* is idempotent — reassigns variables, updates MSG_FIELD_PASSWORD)
case "${DC_FAMILY}" in
    fedora)   _LIVEUSER_LABEL="liveuser" ;;
    arch)     _LIVEUSER_LABEL="archie"   ;;
    opensuse) _LIVEUSER_LABEL="linux"    ;;
    *)        _LIVEUSER_LABEL="admin"    ;;
esac
case "$DISTROCLONE_LANG" in
    it) load_lang_it ;;
    fr) load_lang_fr ;;
    es) load_lang_es ;;
    de) load_lang_de ;;
    pt) load_lang_pt ;;
    *)  load_lang_en ;;
esac

# Update IM_CMD after package installation
IM_CMD=""
command -v magick >/dev/null 2>&1 && IM_CMD="magick"
[ -z "$IM_CMD" ] && command -v convert >/dev/null 2>&1 && IM_CMD="convert" 

############################################
# [1/30] GUI TOOL SELECTION (YAD FIRST)
############################################
echo "$MSG_STEP1"

if command -v yad >/dev/null 2>&1; then
    GUI_TOOL="yad"
elif command -v zenity >/dev/null 2>&1; then
    GUI_TOOL="zenity"
else
    GUI_TOOL="tty"
fi
echo " $MSG_GUI_SELECTED: $GUI_TOOL"

############################################
# [2/30] GUI QUESTION WRAPPER (YAD FIRST)
############################################
echo "$MSG_STEP2"

gui_question() {
    local TITLE="$1"
    local TEXT="$2"
    local WIDTH="${3:-550}"
    local HEIGHT="${4:-300}"

    case "$GUI_TOOL" in
        yad)
            yad --question \
                --title="$TITLE" \
                --text="$TEXT" \
                --image="dialog-question" \
                --button="$MSG_BTN_YES:0" \
                --button="$MSG_BTN_NO:1" \
                --buttons-layout=spread \
                --center \
                --width="$WIDTH" \
                --height="$HEIGHT"
            return $?
            ;;
        zenity)
            zenity --question \
                --title="$TITLE" \
                --text="$TEXT" \
                --width="$WIDTH" \
                --height="$HEIGHT" 2>/dev/null
            return $?
            ;;
        *)
            read -rp "$TEXT [$MSG_TTY_YN]: " ans
            [[ "$ans" =~ ^[Yy]$ ]]
            return $?
            ;;
    esac
}

############################################
# [3/30] WELCOME SCREEN
############################################
echo "$MSG_STEP3"

# Detect which GUI tool to use
if command -v yad >/dev/null 2>&1; then
    GUI_TOOL="yad"
    echo "  $MSG_YAD_DETECTED"
elif command -v zenity >/dev/null 2>&1; then
    GUI_TOOL="zenity"
    echo "  $MSG_ZENITY_DETECTED"
else
    GUI_TOOL="none"
    echo "$MSG_NO_GUI"
fi

# Generate temporary DistroClone logo for YAD
TEMP_LOGO="$(get_dc_logo 256)"

# Close any transient YAD windows before the welcome dialog
close_yad_windows
rm -f /tmp/distroClone-splash.png 2>/dev/null

# Show welcome screen
if [ "$GUI_TOOL" = "yad" ]; then
    # ===== YAD INTERFACE (ADVANCED) =====
    RESULT=$(yad --form \
        --title="$MSG_WELCOME_TITLE" \
        --window-icon="$TEMP_LOGO" \
        ${TEMP_LOGO:+--image="$TEMP_LOGO"} \
        --image-on-top \
        --width=750 --height=550 \
        --text="<big><b>$MSG_WELCOME_HEADING</b></big>\n\
<i>$MSG_WELCOME_SUBTITLE</i>\n\n\
<b>$MSG_SYSTEM_DETECTED:</b>\n\
  • $MSG_DISTRO: <b>$DISTRO_PRETTY</b>\n\
  • $MSG_DESKTOP: <b>$DESKTOP_ENV</b>\n\
  • Kernel: $(uname -r)\n\
  • Architecture: $(uname -m)\n\n\
<b>$MSG_ISO_CREATED:</b>\n\
  • Name: <b>$ISO_NAME</b>\n\
  • Label: $ISO_LABEL\n\n\
<span color='#666666'><i>$MSG_BUILD_CONFIG</i></span>" \
        --separator="|" \
        --field="$MSG_FIELD_COMPRESSION":CB "$MSG_COMP_STANDARD!$MSG_COMP_FAST!$MSG_COMP_MAX" \
        --field="$MSG_FIELD_PASSWORD":H "root" \
        --field="$MSG_FIELD_HOSTNAME":TEXT "${DISTRO_ID}-live" \
        --field=" ":LBL "" \
        --field="<span color='#0d47a1'><b>$MSG_MIN_REQUIREMENTS</b></span>:":LBL "" \
        --field="<span color='#666666'>$MSG_MIN_REQ_TEXT</span>:":LBL "" \
        --button="$MSG_BTN_CANCEL:1" \
        --button="$MSG_BTN_NEXT:0" \
        2>/dev/null)
    
    DIALOG_EXIT=$?
    
    # Cleanup temporary logo — only if it is a generated file in /tmp/ (not APPDIR/DC_SHARE read-only)
    [[ "${TEMP_LOGO:-}" == /tmp/* ]] && rm -f "$TEMP_LOGO" 2>/dev/null || true
    
    if [ $DIALOG_EXIT -ne 0 ]; then
        echo ""
        echo "$MSG_BUILD_CANCELED"
        exit 0
    fi
    
    # Parse YAD results
    COMPRESSION_CHOICE=$(echo "$RESULT" | cut -d'|' -f1)
    CUSTOM_ROOT_PASSWORD=$(echo "$RESULT" | cut -d'|' -f2)
    CUSTOM_HOSTNAME=$(echo "$RESULT" | cut -d'|' -f3)

    # Determine compression type
    case "$COMPRESSION_CHOICE" in
        *lz4*)
            SQUASHFS_COMP="lz4"
            ;;
        *xz+bcj*|*xz*bcj*)
            SQUASHFS_COMP="xz-bcj"
            ;;
        *)
            SQUASHFS_COMP="xz"
            ;;
    esac
    
   # Update root password if specified
    [ -n "$CUSTOM_ROOT_PASSWORD" ] && ROOT_PASSWORD="$CUSTOM_ROOT_PASSWORD"
    [ -n "$CUSTOM_HOSTNAME" ] && LIVE_HOSTNAME="$CUSTOM_HOSTNAME"
    
    echo ""
    
    echo ""
    echo "$MSG_CHOSEN_CONFIG"
    echo "  • $MSG_COMPRESSION: $SQUASHFS_COMP"
    echo "  • Password root: $([ "$ROOT_PASSWORD" = "root" ] && echo "default (root)" || echo "personalized")"
    echo ""

elif [ "$GUI_TOOL" = "zenity" ]; then
    # ===== ZENITY INTERFACE (FALLBACK) =====
    zenity --info \
        --title="$MSG_WELCOME_TITLE" \
        --icon-name="drive-harddisk" \
        --width=650 --height=450 \
        --text="<big><b>$MSG_WELCOME_HEADING</b></big>\n\n\
<b>$MSG_WELCOME_SUBTITLE</b>\n\n\
<span color='#0d47a1'><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></span>\n\n\
<b>$MSG_SYSTEM_DETECTED:</b>\n\
  • $MSG_DISTRO: <b>$DISTRO_PRETTY</b>\n\
  • $MSG_DESKTOP: <b>$DESKTOP_ENV</b>\n\
  • Kernel: $(uname -r)\n\
  • Architecture: $(uname -m)\n\n\
<b>$MSG_ISO_GENERATED:</b>\n\
  • <b>$ISO_NAME</b>\n\n\
<span color='#0d47a1'><b>━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━</b></span>\n\n\
<b>$MSG_MIN_REQUIREMENTS:</b>\n\
  $MSG_MIN_REQ_TEXT\n\n\
<b>$MSG_PROCESS:</b> $MSG_PROCESS_TEXT\n\n\
<i>$MSG_PRESS_OK</i>" \
        2>/dev/null || {
            echo "$MSG_BUILD_CANCELED"
            exit 0
        }
    
    # With Zenity, use default configurations
    SQUASHFS_COMP="xz"
    echo ""
    echo "$MSG_DEFAULT_CONFIG $MSG_ZENITY_MODE:"
    echo "  • $MSG_COMPRESSION: xz (standard)"
    echo "  • $MSG_PASSWORD_ROOT: root ($MSG_DEFAULT_ROOT)"
    echo ""

else

    # ===== TERMINAL MODE (NO GUI) =====
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                 DISTROCLONE $MSG_TTY_UNIVERSAL                    ║"
    echo "║          $MSG_TTY_LIVEISOBUILDER                 ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  $MSG_VERSION: 1.3.6"
    echo "  $MSG_TTY_DATE: $(date '+%Y-%m-%d %H:%M')"
    echo ""
    echo "$MSG_TTY_SYSTEM_DETECTED:"
    echo "  ├─ $MSG_DISTRO: $DISTRO_PRETTY"
    echo "  ├─ $MSG_DESKTOP: $DESKTOP_ENV"
    echo "  ├─ $MSG_KERNEL: $(uname -r)"
    echo "  └─ $MSG_ARCHITECTURE: $(uname -m)"
    echo ""
    echo "$MSG_TTY_ISO_GENERATED:"
    echo "  └─ $MSG_NAME: $ISO_NAME"
    echo ""
    echo "$MSG_TTY_REQUIREMENTS:"
    echo "  • $MSG_TTY_DISKSPACE"
    echo "  • $MSG_TTY_RAM"
    echo "  • $MSG_TTY_TIME"
    echo ""
    read -p "$MSG_PROCEED_BUILD ($MSG_TTY_PROCEED_YN): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "$MSG_BUILD_CANCELLED"
        exit 0
    fi
    
    # Use default configurations
    SQUASHFS_COMP="xz"
    echo ""
    echo "$MSG_DEFAULT_CONFIG:"
    echo "  • $MSG_COMPRESSION: xz (standard)"
    echo "  • $MSG_PASSWORD_ROOT: root ($MSG_DEFAULT_ROOT)"
    echo ""
fi

   # Start real-time log window
LOG_PID=""

TEMP_LOGO="$(get_dc_logo 128)"
: > "$DC_LOG_FILE"   # crea/azzera il file log

if [ "$GUI_TOOL" = "yad" ]; then
    # Fix 48: tail -f | yad (stdin) instead of --filename for universal compatibility.
    # YAD 7.x (Ubuntu 22.04) does not do file-watching with --filename+--tail: loads the
    # file ONCE on open (empty) and does not update. YAD 12+ (Arch/Fedora) does.
    # With tail -f: content arrives via stdin in real-time on ALL YAD versions.
    # SIGPIPE: the pipe is between tail and yad (separate processes) — when the user closes
    # the yad window, yad exits, tail receives SIGPIPE and dies silently. Our
    # script writes to DC_LOG_FILE via fd 3 (real file, never blocked by SIGPIPE).
    tail -f "$DC_LOG_FILE" 2>/dev/null | \
    yad --text-info \
        --title="$MSG_BUILDLOG_TITLE" \
        ${TEMP_LOGO:+--window-icon="$TEMP_LOGO"} \
        --back="#1a1a2e" \
        --fore="#00e676" \
        --fontname="Monospace 11" \
        --width=500 --height=400 \
        --tail \
        --no-edit \
        --button="$MSG_BTN_HIDE:0" \
        --center \
        2>/dev/null &
    LOG_PID=$!
fi

exec 3>>"$DC_LOG_FILE"
# Trap already set at the start (close_yad_windows)

   # Function to write to both terminal and log window
log_msg() {
    echo "$@"
    echo "$@" >&3 2>/dev/null || true
}


############################################
# [3x1/30] Cleanup pre build
############################################
log_msg "$MSG_STEP3x1"

# Cleanup leftovers from previous builds
rm -rf /etc/calamares 2>/dev/null || true
rm -rf /usr/share/calamares/branding 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true

############################################
# [4/30] CONFIG
############################################
log_msg "$MSG_STEP4"

SOURCE="/"
LIVE_DIR="/mnt/${DISTRO_ID}_live"
DEST="$LIVE_DIR/rootfs"
ISO_DIR="$LIVE_DIR/iso"

# Live username depends on the distro family
# (set after distro detection; this is the initial default)
LIVE_USER="admin"
LIVE_PASSWORD="${ROOT_PASSWORD:-root}"
LIVE_FULLNAME="${DISTRO_NAME} Live User"
LIVE_HOSTNAME="${LIVE_HOSTNAME:-${DISTRO_ID}}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"

############################################
# [5/30] Cleanup previous mounts (if script was interrupted)
############################################
log_msg "$MSG_STEP5"

umount -l "$LIVE_DIR/rootfs/var/cache/pacman/pkg" 2>/dev/null || true
umount -l "$LIVE_DIR/rootfs/proc" "$LIVE_DIR/rootfs/sys" \
       "$LIVE_DIR/rootfs/dev/pts" "$LIVE_DIR/rootfs/dev" \
       "$LIVE_DIR/rootfs/run" "$LIVE_DIR/rootfs/tmp" 2>/dev/null || true
# Unmount $DEST bind-to-itself (mount --bind DEST DEST from bind_chroot_mounts)
umount -l "$LIVE_DIR/rootfs" 2>/dev/null || true

rm -rf "/mnt/${DISTRO_ID}_live"
mkdir -p "/mnt/${DISTRO_ID}_live"

############################################
# [6/30] PREP DIRECTORY
############################################
log_msg "$MSG_STEP6"

rm -rf "$LIVE_DIR"
mkdir -p "$DEST" "$ISO_DIR"/{live,isolinux,boot/grub,EFI/BOOT}

############################################
# [7/30] [PRE] SOURCE & MOUNT SANITY CHECK
############################################

log_msg "$MSG_STEP7"

# SOURCE must be /
if [ "$SOURCE" != "/" ]; then
    log_msg "$(eval echo "$MSG_ERR_SOURCE")"
    exit 1
fi

# DEST must not be mounted
if mount | grep -q " $DEST "; then
    log_msg "$MSG_ERR_DEST_MOUNTED"
    exit 1
fi

# LIVE_DIR must not be mounted
if mount | grep -q " $LIVE_DIR "; then
    log_msg "$MSG_ERR_LIVEDIR_MOUNTED"
    exit 1
fi

# Warn if multiple root filesystems exist
ROOT_FS_COUNT=$(df -hT | awk '$7=="/" {c++} END {print c+0}')
if [ "$ROOT_FS_COUNT" -ne 1 ]; then
    log_msg "$MSG_WARN_MULTI_ROOT"
fi

############################################
# [8/30] CLONAZIONE SISTEMA
############################################
log_msg "$MSG_STEP8"

rsync -aAXH --numeric-ids --info=progress2 --one-file-system \
  --exclude=/dev/* \
  --exclude=/proc/* \
  --exclude=/sys/* \
  --exclude=/run/* \
  --exclude=/tmp/* \
  --exclude=/mnt/* \
  --exclude=/media/* \
  --exclude=/lost+found \
  --exclude=/swapfile \
  --exclude="$LIVE_DIR" \
  --exclude=/home/* \
  --exclude=/root/* \
  --exclude=/var/cache/apt/archives/* \
  --exclude=/var/lib/apt/lists/* \
  --exclude=/var/log/* \
  --exclude=/var/tmp/* \
  --exclude=/etc/NetworkManager/system-connections/* \
  --exclude=/usr/share/distroClone \
  --exclude=/usr/bin/distroClone \
  --exclude=/usr/share/applications/distroClone.desktop \
  --exclude=/usr/share/polkit-1/actions/com.github.distroClone.policy \
  --exclude=/usr/share/man/man1/distroClone.1.gz \
  --exclude=/usr/share/icons/hicolor/*/apps/distroClone.png \
  --exclude=/snap \
  --exclude=/snap/* \
  --exclude=/var/snap \
  --exclude=/var/lib/snapd \
  --exclude=/.snapshots \
  --exclude=/.snapshots/* \
  --exclude=/var/cache/zypp \
  --exclude=/var/cache/zypp/* \
  --exclude=/var/cache/zypper \
  --exclude=/var/cache/zypper/* \
  --exclude=/var/lib/zypp/cache \
  --exclude=/var/lib/zypp/packages \
  --exclude=/var/lib/snapper \
  --exclude=/var/lib/snapper/* \
  --exclude=/etc/snapper/configs/root \
  "$SOURCE" "$DEST" || { RC=$?; [ $RC -eq 24 ] && true || exit $RC; }

mkdir -p "$DEST"/{var/log,var/tmp}
chmod 1777 "$DEST/var/tmp"

# FORCE: Rimuovi completamente /home/* per sicurezza
echo "  $MSG_FORCED_CLEAN_HOME"
rm -rf "$DEST"/home/*
rm -rf "$DEST"/root/*

mkdir -p "$DEST"/{var/log,var/tmp}

# Non eliminare proc/sys/run: necessari per bind mount corretti
umount -lf "$DEST/run" "$DEST/proc" "$DEST/sys" 2>/dev/null || true
rm -rf "$DEST/snap" "$DEST/var/snap" "$DEST/var/lib/snapd"
mkdir -p "$DEST"/{run,proc,sys}

# ── Cleanup snapper state inherited from HOST (prevents phantom snapshots) ──
# Always-run: clear /.snapshots/* and /var/lib/snapper/snapshots/* contents.
# These are HOST-specific state (host btrfs snapshots + their metadata); the
# clone will regenerate them at first boot via dc-firstboot.service.
rm -rf "$DEST/.snapshots"/* 2>/dev/null || true
rm -rf "$DEST/var/lib/snapper/snapshots"/* 2>/dev/null || true

# Arch family (CachyOS etc.): /etc/snapper/configs/root was excluded from
# rsync above (line ~1984) — restore it from SOURCE so snapper works on the
# clone without waiting for dc-firstboot create-config. dc-firstboot will
# only create a fresh config if this restore fails.
if [ "${DC_FAMILY:-}" != "opensuse" ] && [ -f "$SOURCE/etc/snapper/configs/root" ]; then
    mkdir -p "$DEST/etc/snapper/configs"
    cp -a "$SOURCE/etc/snapper/configs/root" "$DEST/etc/snapper/configs/root" 2>/dev/null && \
        echo "  [DC] ✓ Snapper: config 'root' copiata dal source (preservata per ${DC_FAMILY:-unknown})"
fi

# openSUSE-only: remove snapper config + disable snapper-grub-plugin scripts.
# On CachyOS/Arch we PRESERVE /etc/snapper/configs/root (inherited from source
# — dc-firstboot only runs `snapper create-config /` if this file is missing).
# The /etc/grub.d/8?_suse_btrfs_snapshot scripts do not exist on Arch family.
if [ "${DC_FAMILY:-}" = "opensuse" ]; then
    rm -f  "$DEST/etc/snapper/configs/root" 2>/dev/null || true
    if [ -f "$DEST/etc/sysconfig/snapper" ]; then
        sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS=""/' "$DEST/etc/sysconfig/snapper" 2>/dev/null || true
    fi
    for _sg in "$DEST"/etc/grub.d/80_suse_btrfs_snapshot \
               "$DEST"/etc/grub.d/81_suse_btrfs_snapshot; do
        [ -x "$_sg" ] && chmod -x "$_sg" || true
    done
    echo "  [DC] ✓ Snapper: stato host+config rimossi da \$DEST (openSUSE)"
else
    echo "  [DC] ✓ Snapper: stato host pulito (config preservata per ${DC_FAMILY:-unknown})"
fi

# Arch-compliant recursive bind mounts (come arch-chroot ufficiale)
bind_chroot_mounts() {
  # CRITICAL: bind mount $DEST to itself → $DEST appears as a real mount point
  # in /proc/self/mountinfo. Without this, pacman cannot find
  # the root mount point '/' and fails with "could not determine root mount point /".
  mountpoint -q "$DEST" || mount --bind "$DEST" "$DEST"
  mount --make-rslave "$DEST"

  for d in proc sys dev run; do
    mkdir -p "$DEST/$d"
    mount --rbind "/$d" "$DEST/$d"
    mount --make-rslave "$DEST/$d"
  done

  # Dedicated pacman cachedir: explicit bind mount to show libalpm
  # a real and stable mountpoint inside the chroot.
  HOST_PACMAN_CACHE="/mnt/.distroclone-pacman-cache"
  mkdir -p "$HOST_PACMAN_CACHE" "$DEST/var/cache/pacman/pkg"
  mountpoint -q "$DEST/var/cache/pacman/pkg" || mount --bind "$HOST_PACMAN_CACHE" "$DEST/var/cache/pacman/pkg"
  mount --make-rslave "$DEST/var/cache/pacman/pkg"
}

# Cleanup mounts after chroot operations
cleanup_chroot_mounts() {
  if mountpoint -q "$DEST/var/cache/pacman/pkg"; then
    umount -R "$DEST/var/cache/pacman/pkg" 2>/dev/null || umount -l "$DEST/var/cache/pacman/pkg" 2>/dev/null || true
  fi

  for d in dev proc sys run; do
    if mountpoint -q "$DEST/$d"; then
      umount -R "$DEST/$d" 2>/dev/null || umount -l "$DEST/$d" 2>/dev/null || true
    fi
  done

  # $DEST last (bind to itself — like arch-chroot)
  if mountpoint -q "$DEST"; then
    umount "$DEST" 2>/dev/null || umount -l "$DEST" 2>/dev/null || true
  fi
}

log_msg "$MSG_STEP9"

if [ -z "$DEST" ] || [ ! -d "$DEST" ]; then
    log_msg "$MSG_ERR_DEST_NOTSET"
else
    # Remove DistroClone package (not needed in live)
    #chroot "$DEST" dpkg --purge distroclone 2>/dev/null || true

    # Clean package cache (cross-distro)
    case "${DC_FAMILY:-arch}" in
        arch)    chroot "$DEST" pacman -Scc --noconfirm 2>/dev/null || true ;;
        fedora)  chroot "$DEST" dnf clean all 2>/dev/null || true ;;
        *)       : ;;
    esac

    # YAD: non rimuovere il binario con rm -f (bypassa pacman, rompe dipendenze).
    # yad nel clone è necessario per il live installer (Calamares, dc-scripts).
    # dc-remove-live-user.sh (Calamares post-install) lo gestisce se opportuno.
fi

############################################
# [10/30] MOUNT CHROOT
############################################
log_msg "$MSG_STEP10"

bind_chroot_mounts
# DO NOT bind-mount /tmp: step 13 does "rm -rf $DEST/tmp/*" which with the bind mount
# would delete HOST /tmp/* including DC_TMP (where AppImage scripts live).
# The chroot sees $DEST/tmp/ as its own /tmp/ without a bind mount.
mkdir -p "$DEST/tmp"
chmod 1777 "$DEST/tmp"

############################################
# [11/30] REMOVE HOST USERS
############################################
log_msg "$MSG_STEP11"

# Correct LIVE_USER for each family:
# - Arch/Fedora/openSUSE: live user created IN THE CHROOT → remove ALL
#   host users with UID >= 1000 without exceptions (_STEP11_LIVE_USER="")
# - Debian/Ubuntu: preserve the live user (already present in the clone)
case "${DC_FAMILY:-arch}" in
    arch|fedora|opensuse) _STEP11_LIVE_USER="" ;;
    *)       _STEP11_LIVE_USER="${LIVE_USER:-admin}" ;;
esac

for u in $(awk -F: '$3>=1000 && $3<65534 {print $1}' "$DEST/etc/passwd"); do
  if [ -z "$_STEP11_LIVE_USER" ] || [ "$u" != "$_STEP11_LIVE_USER" ]; then
    # Remove primary entry from all shadow files
    sed -i "/^${u}:/d" "$DEST/etc/passwd"  2>/dev/null || true
    sed -i "/^${u}:/d" "$DEST/etc/shadow"  2>/dev/null || true
    sed -i "/^${u}:/d" "$DEST/etc/group"   2>/dev/null || true
    sed -i "/^${u}:/d" "$DEST/etc/gshadow" 2>/dev/null || true
    # Also remove ghost references in secondary groups
    # (e.g. wheel:x:998:edmond,other → wheel:x:998:other)
    sed -i "s/,${u}\b//g; s/\b${u},//g; s/^\\(${u}\\b.*\\)$//" \
        "$DEST/etc/group" "$DEST/etc/gshadow" 2>/dev/null || true
  fi
  rm -rf "$DEST/home/$u"
done

############################################
# [12/30] FIX BOOT DIRECTORY
############################################
log_msg "$MSG_STEP12"

mkdir -p "$DEST/boot/grub" "$DEST/boot/efi"
chmod 755 "$DEST/boot" "$DEST/boot/grub" "$DEST/boot/efi"

# SAFETY: never use the host /boot for writing from the Arch chroot.
# If /boot is separate and rsync did not carry the kernel into the clone,
# copy it HERE from the host to $DEST/boot, without bind mount and without /proc/1/root.
if [ "${DC_FAMILY:-arch}" = "arch" ] && ! compgen -G "$DEST/boot/vmlinuz-*" >/dev/null 2>&1; then
    echo "[DC] Arch: clone /boot has no kernel — one-shot copy from host"
    mkdir -p "$DEST/boot"
    _host_k=$(ls /boot/vmlinuz-* 2>/dev/null | grep -v fallback | head -n1)
    if [ -n "$_host_k" ] && [ -f "$_host_k" ]; then
        cp -a "$_host_k" "$DEST/boot/"
        echo "[DC] ✓ kernel copied to $DEST/boot: $(basename "$_host_k")"
    else
        echo "[DC] WARN: no kernel found in host /boot"
    fi
fi

############################################
# [13/30] PRE-CLEANUP
############################################
log_msg "$MSG_STEP13"

rm -rf "$DEST"/var/cache/apt/archives/*.deb
rm -rf "$DEST"/var/lib/apt/lists/*
rm -rf "$DEST"/var/log/*.log
rm -rf "$DEST"/tmp/*
rm -rf "$DEST"/root/.bash_history
rm -rf "$DEST"/home/*/.bash_history

# MINIMAL and TARGETED cleanup - Preserves theme/icons/Plank/configurations
# Bluetooth - paired devices
rm -rf "$DEST"/var/lib/bluetooth/* 2>/dev/null || true

for homedir in "$DEST"/home/* "$DEST"/root; do
  [ -d "$homedir" ] || continue
  
  # GTK recent files (file open dialogs)
  rm -f "$homedir"/.local/share/recently-used.xbel* 2>/dev/null || true

  # Thumbnail cache
  rm -rf "$homedir"/.cache/thumbnails 2>/dev/null || true
  rm -rf "$homedir"/.thumbnails 2>/dev/null || true

  # Browser cache (optional)
  rm -rf "$homedir"/.mozilla 2>/dev/null || true
  rm -rf "$homedir"/.config/chromium 2>/dev/null || true
  rm -rf "$homedir"/.config/google-chrome 2>/dev/null || true

  # Nextcloud configurations (folders and client)
  rm -rf "$homedir"/.config/Nextcloud 2>/dev/null || true
  rm -rf "$homedir"/.config/nextcloud 2>/dev/null || true
  rm -rf "$homedir"/Nextcloud 2>/dev/null || true
  rm -rf "$homedir"/nextcloud 2>/dev/null || true

done

############################################
# [14/30] COPY USER CONFIGURATIONS TO /etc/skel
############################################
log_msg "$MSG_STEP14"

# Generate temporary DistroClone logo for YAD
TEMP_LOGO="$(get_dc_logo 128)"
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    export DISPLAY=:0
fi

if [ "$GUI_TOOL" = "yad" ]; then
    if yad --question \
        --title="$MSG_USERCONF_TITLE" \
        --window-icon="$TEMP_LOGO" \
        ${TEMP_LOGO:+--image="$TEMP_LOGO"} \
        --button="$MSG_BTN_NO:1" \
        --button="$MSG_BTN_YES:0" \
        --buttons-layout=spread \
        --center \
        --width=550 --height=400 \
        --fixed \
        --text="$MSG_USERCONF_HEADING\n\n$MSG_USERCONF_TEXT"; then
        COPY_USER_CONFIG=true
    else
        COPY_USER_CONFIG=false
    fi
elif [ "$GUI_TOOL" = "zenity" ]; then
    if zenity --question \
        --title="$MSG_USERCONF_TITLE" \
        --text="$MSG_USERCONF_HEADING\n\n$MSG_USERCONF_TEXT" \
        --width=550 --height=300 --timeout=60 2>/dev/null; then
        COPY_USER_CONFIG=true
    else
        COPY_USER_CONFIG=false
    fi
else
    read -p "$MSG_TTY_COPY_CONFIG ($MSG_TTY_PROCEED_YN): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        COPY_USER_CONFIG=true
    else
        COPY_USER_CONFIG=false
    fi
fi
  
if [ "$COPY_USER_CONFIG" = true ]; then
    # Identify the current user (non-root)
    CURRENT_USER=$(logname 2>/dev/null || echo $SUDO_USER)
    if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "root" ]; then
        CURRENT_USER=$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)
    fi

    if [ -n "$CURRENT_USER" ] && [ -d "/home/$CURRENT_USER/.config" ]; then
        echo "  $MSG_USER_DETECTED: $CURRENT_USER"

        # Clean skel cloned from host before copying
        rm -rf "$DEST/etc/skel/.config" "$DEST/etc/skel/.local"
        mkdir -p "$DEST/etc/skel/.config"

        # Copy .config excluding sensitive data
        rsync -a --exclude='*.log' \
                 --exclude='*cache*' \
                 --exclude='*Cache*' \
                 --exclude='chromium' \
                 --exclude='google-chrome' \
                 --exclude='mozilla' \
                 --exclude='Code/User/globalStorage' \
                 --exclude='Code/User/workspaceStorage' \
                 --exclude='VirtualBox' \
                 --exclude='nextcloud' \
                 --exclude='Nextcloud' \
                 --exclude='pulse' \
                 --exclude='*.sock' \
                 --exclude='*.pid' \
                 "/home/$CURRENT_USER/.config/" "$DEST/etc/skel/.config/"

        rm -f "$DEST/etc/skel/.config/user-dirs.dirs" 2>/dev/null || true

        # Copy .local/share (icons, custom themes)
        if [ -d "/home/$CURRENT_USER/.local/share" ]; then
            mkdir -p "$DEST/etc/skel/.local/share"
            rsync -a --exclude='Trash' \
                     --exclude='recently-used.xbel*' \
                     "/home/$CURRENT_USER/.local/share/icons" \
                     "/home/$CURRENT_USER/.local/share/themes" \
                     "/home/$CURRENT_USER/.local/share/applications" \
                     "$DEST/etc/skel/.local/share/" 2>/dev/null || true
        fi

        # Copy shell dotfiles
        for f in .profile .bashrc .bash_logout; do
            if [ -f "/home/$CURRENT_USER/$f" ]; then
                cp "/home/$CURRENT_USER/$f" "$DEST/etc/skel/$f"
            fi
        done

        # Fix permissions
        chown -R root:root "$DEST/etc/skel/.config"
        [ -d "$DEST/etc/skel/.local" ] && chown -R root:root "$DEST/etc/skel/.local"

        echo "  $MSG_SKEL_COPIED"
        echo "  $MSG_SKEL_NEWUSERS"
    else
        echo "  $MSG_SKEL_NOTFOUND $CURRENT_USER"
    fi
else
    # User chose NO: clean /etc/skel from host configurations
    echo "  $MSG_SKEL_CLEANING"
    rm -rf "$DEST/etc/skel/.config"
    rm -rf "$DEST/etc/skel/.local"
    # Keep only the default Debian shell dotfiles
    for f in .profile .bashrc .bash_logout; do
        if [ -f "$DEST/etc/skel/$f" ]; then
            echo "  $MSG_SKEL_KEEPING $f"
        fi
    done
    echo "  $MSG_SKEL_DEFAULT"
fi
    
############################################
# [15/30] BRANDING AUTOMATICO
############################################
log_msg "$MSG_STEP15"

# Fixed branding name "distroClone" — avoids conflicts with native distro branding
# (e.g. Fedora has /usr/share/calamares/branding/fedora/ overwritten by dnf)
DC_BRAND_NAME="distroClone"
BRANDING_DIR="$DEST/usr/share/calamares/branding/${DC_BRAND_NAME}"
mkdir -p "$BRANDING_DIR"

# Distribution name formatted for UI (max 20 characters to avoid truncation)
DISTRO_NAME_SHORT=$(echo "${DISTRO_ID}" | tr '[:lower:]' '[:upper:]')

# Check if custom branding files exist
CUSTOM_BRANDING=false

# Logo - Use universal DistroClone logo or generate built-in hexagon
# Search order: DC_SHARE → APPDIR → CWD → ImageMagick
_DC_LOGO_SRC=""
[ -f "${DC_SHARE}/distroClone-logo.png" ]                                             && _DC_LOGO_SRC="${DC_SHARE}/distroClone-logo.png"
[ -z "$_DC_LOGO_SRC" ] && [ -n "${APPDIR:-}" ] && \
    [ -f "${APPDIR}/usr/share/distroClone/distroClone-logo.png" ]                      && _DC_LOGO_SRC="${APPDIR}/usr/share/distroClone/distroClone-logo.png"
[ -z "$_DC_LOGO_SRC" ] && [ -f "distroClone-logo.png" ]                               && _DC_LOGO_SRC="distroClone-logo.png"
if [ -n "$_DC_LOGO_SRC" ]; then
    cp "$_DC_LOGO_SRC" "$BRANDING_DIR/distroClone-logo.png"
    echo "  $MSG_LOGO_COPIED"
    CUSTOM_BRANDING=true
else
    echo "  $MSG_LOGO_NOTFOUND"
    if command -v $IM_CMD >/dev/null 2>&1; then
        $IM_CMD -size 256x256 xc:transparent \
                -fill '#0d47a1' \
                -draw 'polygon 128,6 228,58 228,198 128,250 28,198 28,58' \
                -fill 'none' -strokewidth 5 -stroke '#1976d2' \
                -draw 'polygon 128,28 208,72 208,184 128,228 48,184 48,72' \
                -fill '#2196f3' \
                -draw 'polygon 128,58 184,88 184,168 128,198 72,168 72,88' \
                -fill 'white' -font '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' -pointsize 56 -gravity center \
                -annotate +0+0 'DC' \
                "$BRANDING_DIR/distroClone-logo.png" 2>/dev/null && \
        echo "  $MSG_LOGO_GENERATED"
    fi
fi

# Welcome screen - DC_SHARE → APPDIR → CWD → ImageMagick (search order)
_DC_WELCOME_SRC=""
[ -f "${DC_SHARE}/distroClone-welcome.png" ]                                           && _DC_WELCOME_SRC="${DC_SHARE}/distroClone-welcome.png"
[ -z "$_DC_WELCOME_SRC" ] && [ -n "${APPDIR:-}" ] && \
    [ -f "${APPDIR}/usr/share/distroClone/distroClone-welcome.png" ]                   && _DC_WELCOME_SRC="${APPDIR}/usr/share/distroClone/distroClone-welcome.png"
[ -z "$_DC_WELCOME_SRC" ] && [ -f "distroClone-welcome.png" ]                         && _DC_WELCOME_SRC="distroClone-welcome.png"
if [ -n "$_DC_WELCOME_SRC" ]; then
    cp "$_DC_WELCOME_SRC" "$BRANDING_DIR/welcome.png"
    echo "  $MSG_WELCOME_COPIED"
    CUSTOM_BRANDING=true
else
    echo "  $MSG_WELCOME_NOTFOUND"
    if command -v $IM_CMD >/dev/null 2>&1; then
        $IM_CMD -size 800x400 xc:'#0c0d45' \
                -fill '#ecf0f1' \
                -pointsize 64 \
                -gravity center \
                -annotate +0-50 'DistroClone' \
                -pointsize 28 \
                -fill '#95a5a6' \
                -annotate +0+30 'Universal Live ISO Builder' \
                "$BRANDING_DIR/welcome.png" 2>/dev/null
    fi
fi

# Optional slides
cp -v slide*.png "$BRANDING_DIR/" 2>/dev/null || true

# Genera branding.desc
echo "  $MSG_BRANDING_DESC"
cat > "$BRANDING_DIR/branding.desc" << EOBRAND
---
componentName: distroClone

images:
    productLogo: "distroClone-logo.png"
    productIcon: "distroClone-logo.png"
    productWelcome: "welcome.png"

slideshow: "show.qml"
slideshowAPI: 2

strings:
    productName: "${DISTRO_NAME_SHORT} ${DISTRO_VERSION}"
    shortProductName: "${DISTRO_ID}"
    version: "${DISTRO_VERSION}"
    shortVersion: "${DISTRO_VERSION}"
    versionedName: "${DISTRO_NAME_SHORT} ${DISTRO_VERSION}"
    shortVersionedName: "${DISTRO_ID} ${DISTRO_VERSION}"
    bootloaderEntryName: "${DISTRO_ID}"
    productUrl: "https://www.debian.org/"
    supportUrl: "https://www.debian.org/support"
    knownIssuesUrl: "https://www.debian.org/"
    releaseNotesUrl: "https://www.debian.org/"

style:
    SidebarBackground: "#0a0a36"
    SidebarBackgroundCurrent: "#2196f3"
    SidebarText: "#FFFFFF"
    SidebarTextCurrent: "#0a0a36"
    sidebarBackground: "#0a0a36"
    sidebarBackgroundCurrent: "#2196f3"
    sidebarText: "#FFFFFF"
    sidebarTextCurrent: "#0a0a36"

welcomeStyleCalamares: true
EOBRAND

# Genera show.qml
echo "  $MSG_BRANDING_QML"
cat > "$BRANDING_DIR/show.qml" << EOQML
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }
    
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0a0a36"
            
            Column {
                anchors.centerIn: parent
                spacing: 20
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "$MSG_QML_INSTALLING"
                    font.pointSize: 28
                    font.bold: true
                    color: "white"
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "$MSG_QML_WAIT"
                    font.pointSize: 16
                    color: "#ecf0f1"
                }
            }
        }
    }
    
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0a0a36"
            
            Column {
                anchors.centerIn: parent
                spacing: 20
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "$MSG_QML_CONFIGURING"
                    font.pointSize: 28
                    font.bold: true
                    color: "white"
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "$MSG_QML_SERVICES"
                    font.pointSize: 16
                    color: "#ecf0f1"
                }
            }
        }
    }
    
    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0a0a36"
            
            Column {
                anchors.centerIn: parent
                spacing: 20
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "$MSG_QML_ALMOST"
                    font.pointSize: 28
                    font.bold: true
                    color: "white"
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "$MSG_QML_COMPLETE"
                    font.pointSize: 16
                    color: "#ecf0f1"
                }
            }
        }
    }
}
EOQML

echo "$MSG_BRANDING_DONE: $BRANDING_DIR"
ls -lh "$BRANDING_DIR/" | sed 's/^/  /'

# Copia icona installer DistroClone — DC_SHARE → APPDIR → CWD → ImageMagick
_DC_INST_SRC=""
[ -f "${DC_SHARE}/distroClone-installer.png" ]                                         && _DC_INST_SRC="${DC_SHARE}/distroClone-installer.png"
[ -z "$_DC_INST_SRC" ] && [ -n "${APPDIR:-}" ] && \
    [ -f "${APPDIR}/usr/share/distroClone/distroClone-installer.png" ]                 && _DC_INST_SRC="${APPDIR}/usr/share/distroClone/distroClone-installer.png"
[ -z "$_DC_INST_SRC" ] && [ -f "distroClone-installer.png" ]                          && _DC_INST_SRC="distroClone-installer.png"
if [ -n "$_DC_INST_SRC" ]; then
    cp "$_DC_INST_SRC" "$DEST/usr/share/icons/install-system.png"
    echo "  $MSG_INSTALLER_COPIED"
else
    echo "  $MSG_INSTALLER_NOTFOUND"
    if command -v $IM_CMD >/dev/null 2>&1; then
        $IM_CMD -size 256x256 xc:transparent \
                -fill '#0d47a1' \
                -draw 'polygon 128,6 228,58 228,198 128,250 28,198 28,58' \
                -fill 'none' -strokewidth 5 -stroke '#1976d2' \
                -draw 'polygon 128,28 208,72 208,184 128,228 48,184 48,72' \
                -fill '#2196f3' \
                -draw 'polygon 128,58 184,88 184,168 128,198 72,168 72,88' \
                -fill 'white' -font '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' -pointsize 56 -gravity center \
                -annotate +0+0 'DC' \
                "$DEST/usr/share/icons/install-system.png" 2>/dev/null && \
        echo "  $MSG_INSTALLER_GENERATED"
    fi
fi

############################################
# [16/30] CHROOT CONFIG
############################################
log_msg "$MSG_STEP16"
log_msg "  $MSG_CHROOT_INSTALLING"

# ── Chroot config branch per famiglia distro ────────────────────────────────
# Ispirato a penguins-eggs/src/classes/pacman.d/{debian,archlinux,fedora}.ts
# ─────────────────────────────────────────────────────────────────────────────

# ══════════════════════════════════════════════════════════════════════════════
# Pre-chroot copy: calamares-config.sh copiato in $DEST/tmp/
# Risoluzione robusta: accetta anche varianti tipo calamares-config-4.sh
# ma copia sempre come $DEST/tmp/calamares-config.sh
# ══════════════════════════════════════════════════════════════════════════════
find_calamares_config() {
    local candidate=""
    local searchdir=""
    DCSCRIPTABS="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")"
    DCSCRIPTDIR="$(dirname "$DCSCRIPTABS")"
    for searchdir in         "$DCSCRIPTDIR"         "${_DC_SELF_DIR:-}"         "${DC_SHARE:-}"         "${APPDIR:+$APPDIR/usr/share/distroClone}"         "/usr/share/distroClone"
    do
        [ -z "$searchdir" ] && continue
        [ ! -d "$searchdir" ] && continue
        # 1) Nome esatto
        if [ -f "$searchdir/calamares-config.sh" ]; then
            echo "$searchdir/calamares-config.sh"
            return 0
        fi
        # 2) Fallback: prima variante compatibile (es. calamares-config-4.sh)
        candidate="$(find "$searchdir" -maxdepth 1 -type f -name 'calamares-config*.sh' | sort | head -n1)"
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

DCCALCONFSRC="$(find_calamares_config || true)"
if [ -z "$DCCALCONFSRC" ] || [ ! -f "$DCCALCONFSRC" ]; then
    echo "[ERROR] calamares-config.sh non trovato. Cercato in:"
    for p in         "$DCSCRIPTDIR"         "${_DC_SELF_DIR:-}"         "${DC_SHARE:-}"         "${APPDIR:+$APPDIR/usr/share/distroClone}"         "/usr/share/distroClone"
    do
        [ -n "$p" ] && echo "  - $p/calamares-config.sh"
        [ -n "$p" ] && echo "  - $p/calamares-config*.sh"
    done
    echo ""
    echo "[HINT] L'AppImage in uso potrebbe essere obsoleto (build senza calamares-config.sh)."
    echo "       Ricostruire con:  OUTPUT_DIR=/tmp bash build-appimage.sh"
    echo "       Poi copiare il nuovo AppImage sul sistema target e rieseguire."
    exit 1
fi
mkdir -p "$DEST/tmp"
cp -f "$DCCALCONFSRC" "$DEST/tmp/calamares-config.sh"
chmod 755 "$DEST/tmp/calamares-config.sh"
if [ ! -s "$DEST/tmp/calamares-config.sh" ]; then
    echo "[ERROR] copia pre-chroot di calamares-config.sh fallita"
    echo "  Sorgente: $DCCALCONFSRC"
    echo "  Destinazione: $DEST/tmp/calamares-config.sh"
    exit 1
fi
echo "[OK] Calamares config trovata: $DCCALCONFSRC"
echo "[OK] Copiata in: $DEST/tmp/calamares-config.sh"

# Copia moduli famiglia calamares-config
for _cc_mod in calamares-config-arch.sh calamares-config-fedora.sh calamares-config-debian.sh; do
    for _cc_dir in "$DCSCRIPTDIR" "${_DC_SELF_DIR:-}" "${DC_SHARE:-}" \
                   "${APPDIR:+$APPDIR/usr/share/distroClone}" "/usr/share/distroClone"; do
        [ -n "$_cc_dir" ] && [ -f "$_cc_dir/$_cc_mod" ] || continue
        cp -f "$_cc_dir/$_cc_mod" "$DEST/tmp/$_cc_mod"
        chmod 755 "$DEST/tmp/$_cc_mod"
        echo "[OK] Copiato: $DEST/tmp/$_cc_mod"
        break
    done
done

# ── openSUSE: setup calamares con modulo partition (repo home:carluad:greemond) ──
# Il calamares nativo di Tumbleweed non include partition.so (kpmcore Qt6 only).
# Soluzione: repo custom con calamares pre-compilato + partition.so Qt6.
if grep -qi "opensuse\|tumbleweed\|leap" "$DEST/etc/os-release" 2>/dev/null && \
   command -v zypper >/dev/null 2>&1; then

    # URL .repo fornito dall'utente (contiene baseurl, gpgcheck, type corretti)
    _DC_CAL_REPO_FILE_URL="https://download.opensuse.org/repositories/home:carluad:greemond/standard/home:carluad:greemond.repo"

    # 1. Rimuovi qualsiasi versione precedente del repo (run precedenti, VirtualBox, ecc.)
    while IFS= read -r _old; do
        [ -n "$_old" ] && zypper --non-interactive removerepo "$_old" 2>/dev/null || true
        [ -n "$_old" ] && echo "[DC-openSUSE] Rimosso repo precedente: $_old"
    done < <(zypper lr 2>/dev/null | awk -F'|' '/greemond/{gsub(/[[:space:]]/,"",$2); print $2}')

    # Aggiungi dal .repo file — || true: repo già esistente non è un errore fatale
    echo "[DC-openSUSE] Aggiunta repo da .repo file..."
    zypper --non-interactive addrepo "$_DC_CAL_REPO_FILE_URL" 2>&1 | tail -3 || true
    zypper --non-interactive --gpg-auto-import-keys refresh 2>/dev/null || true

    # Rileva alias effettivo — process substitution evita pipefail
    _DC_CAL_REPO_NAME=""
    while IFS= read -r _line; do
        _DC_CAL_REPO_NAME=$(echo "$_line" | awk -F'|' '/greemond/{gsub(/[[:space:]]/,"",$2); print $2; exit}')
        [ -n "$_DC_CAL_REPO_NAME" ] && break
    done < <(zypper lr 2>/dev/null)
    echo "[DC-openSUSE] Alias repo: ${_DC_CAL_REPO_NAME:-NON TROVATO}"

    # Imposta priorità 50 — || true: fallisce su alias vuoto ma non è fatale
    if [ -n "$_DC_CAL_REPO_NAME" ]; then
        zypper --non-interactive modifyrepo --priority 50 \
            "$_DC_CAL_REPO_NAME" 2>&1 | tail -2 || true
        echo "[DC-openSUSE] Repos dopo setup:"
        zypper lr 2>/dev/null | awk -F'|' 'NR>2 && /greemond|OSS|oss/{printf "  %-35s p=%s\n",$3,$7}' || true
        # Copia .repo file nel DEST: rsync è già avvenuto (step 8), quindi il repo OBS
        # non è nella copia clonata. Copiandolo ora il chroot può fare zypper install
        # dalla sorgente corretta (3.4) invece del repo standard Tumbleweed (3.2.x).
        _DC_OBS_REPO_FILE=$(find /etc/zypp/repos.d/ -name "*greemond*" 2>/dev/null | head -1)
        if [ -n "$_DC_OBS_REPO_FILE" ]; then
            mkdir -p "$DEST/etc/zypp/repos.d/"
            cp "$_DC_OBS_REPO_FILE" "$DEST/etc/zypp/repos.d/"
            echo "[DC-openSUSE] ✓ Repo OBS copiato in DEST: $(basename "$_DC_OBS_REPO_FILE")"
        else
            echo "[DC-openSUSE] WARN: .repo file non trovato in /etc/zypp/repos.d/"
        fi
    else
        echo "[DC-openSUSE] WARN: repo non trovato dopo addrepo"
    fi

    # 2. Dipendenza libyaml-cpp0_8 — rpm -ivh || true: "already installed" non è fatale
    if ! rpm -q libyaml-cpp0_8 >/dev/null 2>&1; then
        echo "[DC-openSUSE] Download libyaml-cpp0_8..."
        _DC_YAML_RPM="/tmp/dc-libyaml-cpp0_8-$$.rpm"
        if curl -fsSL --retry 2 --connect-timeout 20 \
               "https://rpmfind.net/linux/opensuse/distribution/leap/16.0/repo/oss/x86_64/libyaml-cpp0_8-0.8.0-160000.2.2.x86_64.rpm" \
               -o "$_DC_YAML_RPM" 2>/dev/null; then
            rpm -ivh --nodeps "$_DC_YAML_RPM" 2>&1 | tail -5 || true
            echo "[DC-openSUSE] ✓ libyaml-cpp0_8 installato"
        else
            echo "[DC-openSUSE] WARN: download libyaml-cpp0_8 fallito"
        fi
        rm -f "$_DC_YAML_RPM"
    else
        echo "[DC-openSUSE] libyaml-cpp0_8 già presente"
    fi

    # 3. Rimuovi calamares nativo dal sistema host
    if rpm -q calamares >/dev/null 2>&1; then
        echo "[DC-openSUSE] Rimozione calamares nativo dal sistema host..."
        zypper --non-interactive remove -y calamares 2>&1 | tail -5 || true
        echo "[DC-openSUSE] ✓ Calamares nativo rimosso"
    fi

    # 4. Installa calamares dal repo custom — || true: errori non fatali (verrà verificato dopo)
    echo "[DC-openSUSE] Installazione calamares custom (home:carluad:greemond, priorità 50)..."
    zypper --non-interactive install -y calamares 2>&1 | tail -20 || true
    if rpm -q calamares >/dev/null 2>&1; then
        echo "[DC-openSUSE] ✓ Calamares installato: $(rpm -q calamares)"
        _DC_PART_SO=""
        while IFS= read -r _f; do _DC_PART_SO="$_f"; break; done < <(
            find /usr/lib64/calamares /usr/lib/calamares \
                -name "partition.so" 2>/dev/null
        )
        if [ -n "$_DC_PART_SO" ]; then
            echo "[DC-openSUSE] ✓ partition.so: $_DC_PART_SO"
        else
            echo "[DC-openSUSE] WARN: partition.so non trovato dopo installazione"
        fi
        # Salva RPM per il chroot: prima cerca nella cache zypper, poi forza download
        _DC_CAL_CACHED_RPM=""
        while IFS= read -r _f; do _DC_CAL_CACHED_RPM="$_f"; break; done < <(
            find /var/cache/zypp/packages -path "*greemond*" \
                -name "calamares-*.rpm" -not -name "*.delta.rpm" 2>/dev/null
        )
        if [ -z "$_DC_CAL_CACHED_RPM" ]; then
            # Fallback: qualsiasi calamares nella cache (versione appena installata)
            _CAL_VER=$(rpm -q --qf '%{VERSION}-%{RELEASE}' calamares 2>/dev/null || true)
            while IFS= read -r _f; do _DC_CAL_CACHED_RPM="$_f"; break; done < <(
                find /var/cache/zypp/packages \
                    -name "calamares-${_CAL_VER}.x86_64.rpm" 2>/dev/null
            )
        fi
        if [ -z "$_DC_CAL_CACHED_RPM" ]; then
            # Cache vuota (zypper non trattiene i pacchetti dopo l'install):
            # forza re-download con zypper download in /var/cache/zypp/packages/
            echo "[DC-openSUSE] Cache RPM vuota — forzo download con zypper download..."
            zypper --non-interactive download calamares 2>&1 | tail -5 || true
            while IFS= read -r _f; do _DC_CAL_CACHED_RPM="$_f"; break; done < <(
                find /var/cache/zypp/packages -path "*greemond*" \
                    -name "calamares-*.rpm" -not -name "*.delta.rpm" 2>/dev/null
            )
            # Ultimo fallback: qualsiasi calamares scaricato
            if [ -z "$_DC_CAL_CACHED_RPM" ]; then
                _CAL_VER=$(rpm -q --qf '%{VERSION}-%{RELEASE}' calamares 2>/dev/null || true)
                while IFS= read -r _f; do _DC_CAL_CACHED_RPM="$_f"; break; done < <(
                    find /var/cache/zypp/packages \
                        -name "calamares-${_CAL_VER}.x86_64.rpm" 2>/dev/null
                )
            fi
        fi
        if [ -n "$_DC_CAL_CACHED_RPM" ]; then
            mkdir -p "$DEST/tmp"
            cp "$_DC_CAL_CACHED_RPM" "$DEST/tmp/dc-calamares-custom.rpm" 2>/dev/null && \
                echo "[DC-openSUSE] ✓ RPM calamares copiato in DEST: $(basename "$_DC_CAL_CACHED_RPM")" || true
        else
            echo "[DC-openSUSE] WARN: RPM calamares non trovato in cache — il chroot userà zypper con repo OBS"
        fi
    else
        echo "[DC-openSUSE] WARN: installazione calamares custom fallita"
    fi
fi

# Scrivi args per il chroot
printf '%s\n%s\n%s\n' \
    "${DC_FAMILY:-arch}" \
    "${DISTRO_ID:-linux}" \
    "distroClone" \
    > "$DEST/tmp/dc_calamares_args"

echo "  → Pre-chroot: calamares-config.sh copiato in $DEST/tmp/"

# Scrivi variabili host in un file che il chroot può leggere
# (heredoc con '' non espande variabili — unico modo affidabile)
_DC_LIVE_USER="admin"
case "${DC_FAMILY:-arch}" in
    fedora)  _DC_LIVE_USER="liveuser" ;;
    arch)    _DC_LIVE_USER="archie" ;;
    opensuse) _DC_LIVE_USER="linux" ;;
esac

mkdir -p "$DEST/tmp"
cat > "$DEST/tmp/dc_env.sh" << DCENV
DC_FAMILY="${DC_FAMILY:-arch}"
DC_LIVE_USER="${_DC_LIVE_USER}"
DC_ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
DC_HOSTNAME="${LIVE_HOSTNAME:-live-system}"
DC_INITRAMFS="${DC_INITRAMFS:-}"
DC_KERNEL_FLAVOR="${DC_KERNEL_FLAVOR:-}"
DC_LIVE_STACK="${DC_LIVE_STACK:-}"
DCENV
chmod 644 "$DEST/tmp/dc_env.sh"
# Scrivi utente live in /etc per il remove-live-admin.service (leggibile post-install)
echo "${_DC_LIVE_USER}" > "$DEST/etc/distroClone-live-user"
chmod 644 "$DEST/etc/distroClone-live-user"
echo "[DC] → Variabili scritte in chroot: famiglia=${DC_FAMILY:-arch}, utente=${_DC_LIVE_USER}"

case "${DC_FAMILY:-arch}" in

  # ════════════════════════════════════════════════════════════════════════════
  # ARCH FAMILY — usa mkinitcpio + archiso al posto di live-boot
  # Ispirato a penguins-eggs/src/classes/pacman.d/archlinux.ts
  # e alla directory mkinitcpio/ del repo penguins-eggs
  # ════════════════════════════════════════════════════════════════════════════
  arch)
    # mounts already active from bind_chroot_mounts at step 10

    # resolv.conf: Arch usa systemd-resolved (symlink a /run/systemd/resolve/)
    # Nel chroot il symlink può essere rotto → copia resolv.conf funzionante dall'host
    if [ ! -s "$DEST/etc/resolv.conf" ] || \
       { [ -L "$DEST/etc/resolv.conf" ] && [ ! -e "$DEST/etc/resolv.conf" ]; }; then
        echo "[DC-Arch] resolv.conf mancante o symlink rotto → copio da host"
        rm -f "$DEST/etc/resolv.conf"
        cp /etc/resolv.conf "$DEST/etc/resolv.conf" 2>/dev/null || \
            echo "nameserver 8.8.8.8" > "$DEST/etc/resolv.conf"
    fi
    echo "[DC-Arch] resolv.conf: $(head -2 "$DEST/etc/resolv.conf" 2>/dev/null)"

    chroot "$DEST" /bin/bash << 'CHROOT_ARCH_EOF'
set -e

# Fix 23 — pacman cachedir nel chroot: usa /var/cache/pacman/pkg (sotto /,
# sempre risolvibile nel namespace mount). NON usare /tmp (non bind-montato)
# né /run (bind-montato dall'host → path mismatch in mountinfo).
# /var è parte del filesystem reale del chroot → pacman trova sempre il
# mount point e calcola correttamente lo spazio disponibile.
mkdir -p /var/cache/pacman/pkg
mountpoint -q /proc || mount -t proc proc /proc
test -r /proc/self/mountinfo || {
    echo "DC-Arch ERROR: /proc/self/mountinfo non disponibile nel chroot"
    exit 1
}
PACMAN_CACHE="$(readlink -f /var/cache/pacman/pkg)"
export PACMAN_CACHE
[ -n "$PACMAN_CACHE" ] && [ -d "$PACMAN_CACHE" ] || {
    echo "DC-Arch ERROR: cachedir pacman non valido: $PACMAN_CACHE"
    exit 1
}
mountpoint -q "$PACMAN_CACHE" || {
    echo "DC-Arch ERROR: cachedir non montato come bind mount: $PACMAN_CACHE"
    grep ' /var/cache/pacman/pkg ' /proc/self/mountinfo || true
    exit 1
}
stat -fc 'DC-Arch cachedir=%m fs=%T path=%n' "$PACMAN_CACHE" >/dev/null 2>&1 || {
    echo "DC-Arch ERROR: impossibile determinare mount/fs del cachedir: $PACMAN_CACHE"
    exit 1
}
echo "DC-Arch DBG cachedir=$PACMAN_CACHE"
grep ' /var/cache/pacman/pkg ' /proc/self/mountinfo || true
_pacman() { pacman --cachedir "$PACMAN_CACHE" "$@"; }
df -hT "$PACMAN_CACHE" || true

# Sincronizza database pacman
_pacman -Sy --noconfirm

# Garuda usa dracut invece di mkinitcpio → rimuovi il pacchetto conflittante
# prima di installare mkinitcpio per la live (Fix 40B)
if pacman -Qi garuda-dracut-support >/dev/null 2>&1; then
    echo "[DC-Arch] Garuda: rimuovo garuda-dracut-support (confligge con mkinitcpio)"
    pacman -Rdd --noconfirm garuda-dracut-support 2>/dev/null || \
        pacman -R --noconfirm --noscriptlet garuda-dracut-support 2>/dev/null || true
fi

# Pacchetti equivalenti live-boot su Arch
_pacman -S --noconfirm --needed \
  mkinitcpio \
  mkinitcpio-archiso \
  archiso \
  grub \
  efibootmgr \
  mtools \
  squashfs-tools \
  rsync \
  cryptsetup \
  lvm2 \
  imagemagick \
  syslinux \
  libisoburn

# os-prober-btrfs (Garuda) confligge con os-prober standard — installa solo se non presente
if ! pacman -Qi os-prober-btrfs >/dev/null 2>&1; then
    _pacman -S --noconfirm --needed os-prober 2>/dev/null || true
else
    echo "[DC-Arch] os-prober-btrfs già presente (Garuda) — skipping os-prober"
fi

# ── Installa calamares ────────────────────────────────────────────────────────
# Logica deterministica a due stadi:
#   A) pacman -Si calamares → già disponibile (CachyOS/Manjaro/clone host)
#   B) chaotic-aur CDN diretto → unico fallback verificato per Arch vanilla
# Tutti i download usano --cachedir sul filesystem host (non nel chroot)
# per evitare "Partition / too full" durante installazione dipendenze grandi.
# Fix 22+34
set +e
_cal_ok=false
_CAL_CACHE="${PACMAN_CACHE:-/var/cache/pacman/pkg}"

# Caso A: già presente nel clone o nei repo correnti
# FIX 33 — clone-di-clone: non basta che il binary esista.
# EndeavourOS (e distro con calamares dai repo ufficiali) compila i file QML
# nel binary come Qt resources → /usr/share/calamares/qml/ assente su disco.
# La nostra configurazione (chaotic-aur) richiede quella directory.
# Se manca, trattiamo come "non installato" e forziamo install da chaotic-aur.
_cal_qml_ok() { [ -d /usr/share/calamares/qml ] || [ -d /usr/lib/calamares/qml ]; }
if command -v calamares >/dev/null 2>&1; then
    if _cal_qml_ok; then
        echo "[DC-Arch] ✓ calamares presente nel clone (con qml/)"
        # Fix 45 — rolling release: verifica librerie linkate (boost/python cambiano spesso)
        # Su CachyOS boost 1.89→1.90: calamares richiede libboost_python314.so.1.89.0
        # ma il sistema ha già 1.90.0 → "not found". boost-python3 non esiste come pkg.
        _CAL_BIN=$(command -v calamares)
        _CAL_MISS=$(ldd "$_CAL_BIN" 2>/dev/null | grep -c "not found" || true)
        if [ "${_CAL_MISS:-0}" -gt 0 ]; then
            echo "[DC-Arch] WARN: $_CAL_MISS librerie mancanti in calamares:"
            ldd "$_CAL_BIN" 2>/dev/null | grep "not found" | head -5

            # Step 1: prova install/upgrade boost-libs e yaml-cpp (entrambi cambiano spesso)
            pacman --cachedir "$_CAL_CACHE" -S --noconfirm --needed boost-libs yaml-cpp 2>/dev/null \
                && ldconfig 2>/dev/null || true
            _CAL_MISS=$(ldd "$_CAL_BIN" 2>/dev/null | grep -c "not found" || true)

            if [ "${_CAL_MISS:-0}" -gt 0 ]; then
                # Step 2: symlink di compatibilità versione (es. 1.89.0→1.90.0, 0.8→0.9.0)
                # ABI boost stabile tra minor; yaml-cpp 0.x: si usa il symlink come fallback
                echo "[DC-Arch] → symlink compatibilità librerie (versione richiesta → disponibile)"
                ldd "$_CAL_BIN" 2>/dev/null | grep "not found" | awk '{print $1}' \
                | while read -r _miss; do
                    # "libboost_python314.so.1.89.0" → base "libboost_python314.so"
                    # "libyaml-cpp.so.0.8"           → base "libyaml-cpp.so"
                    _base=$(echo "$_miss" | sed 's/\.[0-9]\+\.[0-9]\+\.[0-9]\+$//; s/\.[0-9]\+\.[0-9]\+$//')
                    # cerca versione più recente disponibile (tre-parti o due-parti)
                    _avail=$(ls /usr/lib/${_base}.*.*.* /usr/lib/${_base}.*.* 2>/dev/null | sort -V | tail -n1)
                    if [ -n "$_avail" ] && [ -f "$_avail" ]; then
                        ln -sf "$_avail" "/usr/lib/${_miss}" 2>/dev/null \
                            && echo "[DC-Arch] ✓ symlink: ${_miss} → $(basename "$_avail")" \
                            || echo "[DC-Arch] WARN: symlink fallito: ${_miss}"
                    else
                        echo "[DC-Arch] WARN: nessuna versione trovata per ${_base}"
                    fi
                done
                ldconfig 2>/dev/null || true
                _CAL_MISS=$(ldd "$_CAL_BIN" 2>/dev/null | grep -c "not found" || true)
            fi

            if [ "${_CAL_MISS:-0}" -eq 0 ]; then
                echo "[DC-Arch] ✓ dipendenze calamares risolte (boost symlink)"
                _cal_ok=true
            else
                echo "[DC-Arch] librerie ancora mancanti — forzo reinstall da repo/chaotic-aur"
                # _cal_ok rimane false → fallthrough cascata reinstall
            fi
        else
            echo "[DC-Arch] ✓ calamares: tutte le librerie OK"
            _cal_ok=true
        fi
    else
        echo "[DC-Arch] calamares presente ma qml/ assente (build EOS/distro-specifica)"
        echo "[DC-Arch] → reinstallo da chaotic-aur per ottenere versione compatibile"
        # Tenta upgrade/reinstall prima dal repo già configurato
        pacman --cachedir "$_CAL_CACHE" -S --noconfirm calamares 2>/dev/null \
            && _cal_qml_ok && _cal_ok=true || true
    fi
elif pacman -Si calamares >/dev/null 2>&1; then
    echo "[DC-Arch] calamares nei repo correnti → installo"
    pacman --cachedir "$_CAL_CACHE" -S --noconfirm --needed calamares \
        && _cal_ok=true
fi

# Caso B: chaotic-aur CDN diretto (unico fallback per Arch vanilla)
if [ "$_cal_ok" = "false" ]; then
    echo "[DC-Arch] calamares non in repo correnti → aggiungo chaotic-aur"
    # Importa keyring (non bloccante se keyserver irraggiungibile)
    pacman-key --recv-key 3056513887B78AEB \
        --keyserver keyserver.ubuntu.com 2>/dev/null || true
    pacman-key --lsign-key 3056513887B78AEB 2>/dev/null || true
    # Installa keyring e mirrorlist via URL diretto
    pacman --cachedir "$_CAL_CACHE" -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' \
        2>/dev/null || true
    # Aggiungi repo con server CDN diretto (più affidabile della mirrorlist)
    if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
        printf '\n[chaotic-aur]\nServer = https://cdn-mirror.chaotic.cx/$repo/$arch\n' \
            >> /etc/pacman.conf
        echo "[DC-Arch] chaotic-aur aggiunto (CDN diretto)"
    fi
    pacman --cachedir "$_CAL_CACHE" -Sy --noconfirm 2>/dev/null
    # Prova calamares poi calamares-git (chaotic-aur può avere solo il git)
    for _cpkg in calamares calamares-git; do
        if pacman --cachedir "$_CAL_CACHE" -S --noconfirm --needed "$_cpkg" 2>/dev/null; then
            _cal_ok=true
            echo "[DC-Arch] ✓ $_cpkg installato da chaotic-aur"
            break
        fi
    done
fi

# Caso C: build da AUR con makepkg (archie user già creato nel chroot)
# Chaotic-aur non contiene calamares → unico modo affidabile su Arch vanilla
if [ "$_cal_ok" = "false" ]; then
    echo "[DC-Arch] chaotic-aur senza calamares → build da AUR con makepkg"
    # Installa dipendenze di build (calamares AUR usa Qt6 da v3.3+)
    pacman --cachedir "$_CAL_CACHE" -S --noconfirm --needed \
        base-devel git cmake ninja extra-cmake-modules \
        qt6-base qt6-declarative qt6-svg qt6-tools qt6-translations \
        kconfig kcoreaddons ki18n kcrash kdbusaddons kparts kservice \
        kpmcore yaml-cpp libpwquality polkit-qt6 solid icu boost \
        python-yaml python-jsonschema \
        2>/dev/null || true
    # Crea utente temporaneo dedicato (evita nobody/utenti scaduti)
    _BUILD_USER="dc-aur-builder"
    useradd -m -s /bin/bash "$_BUILD_USER" 2>/dev/null || true
    chage -E -1 "$_BUILD_USER" 2>/dev/null || true  # rimuovi scadenza account
    if id "$_BUILD_USER" >/dev/null 2>&1; then
        _CAL_BUILD="/tmp/dc-cal-aur"
        rm -rf "$_CAL_BUILD"
        mkdir -p "$_CAL_BUILD"
        chown "$_BUILD_USER:$_BUILD_USER" "$_CAL_BUILD"
        echo "[DC-Arch] build calamares come utente $_BUILD_USER (può richiedere minuti)..."
        su -c "
            cd '$_CAL_BUILD' &&
            git clone --depth=1 https://aur.archlinux.org/calamares.git &&
            cd calamares &&
            MAKEFLAGS='-j\$(nproc)' makepkg --noconfirm --skippgpcheck 2>&1 | tail -3
        " "$_BUILD_USER" && \
        pacman --cachedir "$_CAL_CACHE" -U --noconfirm \
            "$_CAL_BUILD"/calamares/*.pkg.tar.zst 2>/dev/null && \
        command -v calamares >/dev/null 2>&1 && {
            _cal_ok=true
            echo "[DC-Arch] ✓ calamares installato da AUR (makepkg)"
        }
        rm -rf "$_CAL_BUILD"
        userdel -rf "$_BUILD_USER" 2>/dev/null || true
    fi
fi

if [ "$_cal_ok" = "false" ]; then
    echo "[DC-Arch] WARN: calamares NON installato."
    echo "[DC-Arch]   Soluzione: installa 'calamares' da AUR sull'host PRIMA di eseguire"
    echo "[DC-Arch]   DistroClone (verrà clonato automaticamente):"
    echo "[DC-Arch]     yay -S calamares   oppure   paru -S calamares"
fi
set -e

# Configura mkinitcpio con hook archiso per live system
# L'hook "archiso" monta il filesystem squashfs durante il boot
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
if [ -f "$MKINITCPIO_CONF" ]; then
    # SEMPRE sostituisci HOOKS: rimuove plymouth e altri hook non necessari
    # che causano boot lento/bloccato (plymouth cerca splash= in cmdline)
    sed -i 's/^HOOKS=.*/HOOKS=(base udev archiso block filesystems keyboard fsck)/' \
        "$MKINITCPIO_CONF"
    echo "[DC-Arch] ✓ HOOKS forzati: base udev archiso block filesystems keyboard fsck"

    # SEMPRE imposta MODULES: squashfs+loop (archiso), isofs (mount ISO9660),
    # overlay (overlayfs live), sr_mod+cdrom (CD-ROM in VM/bare metal)
    sed -i 's/^MODULES=.*/MODULES=(squashfs loop isofs overlay sr_mod cdrom)/' \
        "$MKINITCPIO_CONF"
    echo "[DC-Arch] ✓ MODULES forzati: squashfs loop isofs overlay sr_mod cdrom"
fi

# Rigenera initramfs — /boot può essere partizione vfat separata non rsync-ata
# → copia vmlinuz dal host se mancante nella clone
_ensure_kernel_in_chroot() {
    # Trova il kernel nel chroot — stessa logica sort -V | tail -n1 di GRUB (step 20)
    # per garantire coerenza kernel/initramfs (Fix 44)
    local kfile
    kfile=$(ls /boot/vmlinuz-linux* 2>/dev/null | grep -v fallback | sort -V | tail -n1)
    [ -z "$kfile" ] && kfile=$(ls /boot/vmlinuz-* 2>/dev/null | grep -v fallback | sort -V | tail -n1)
    if [ -n "$kfile" ] && [ -f "$kfile" ]; then
        echo "[DC-Arch] → Kernel trovato: $kfile"
        return 0
    fi
    echo "[DC-Arch] WARN: /boot/vmlinuz-* mancante nel chroot — accesso al host disabilitato"
    return 1
}

# Fix 42 — Garuda/dracut: forza mkinitcpio come generatore initramfs
# Su Garuda /etc/kernel/install.conf può avere INITRD_GENERATOR=dracut
# → anche dopo aver rimosso garuda-dracut-support, dracut può vincere
mkdir -p /etc/kernel
echo "INITRD_GENERATOR=mkinitcpio" > /etc/kernel/install.conf
echo "[DC-Arch] INITRD_GENERATOR=mkinitcpio forzato in /etc/kernel/install.conf"

# Fix 42B — Su Garuda i preset mkinitcpio non esistono (dracut non li crea)
# → creali dinamicamente per ogni vmlinuz trovato in /boot
# Usa compgen -G invece di ls per robustezza sotto set -e
_dc_has_mkinitcpio_presets() {
    compgen -G '/etc/mkinitcpio.d/*.preset' > /dev/null 2>&1
}

_dc_create_mkinitcpio_presets() {
    local _created=0 _kf _kname
    mkdir -p /etc/mkinitcpio.d
    for _kf in /boot/vmlinuz-*; do
        [ -f "$_kf" ] || continue
        _kname=$(basename "$_kf" | sed 's/^vmlinuz-//')
        cat > "/etc/mkinitcpio.d/${_kname}.preset" << MKPRESET
ALL_config='/etc/mkinitcpio.conf'
ALL_kver='/boot/vmlinuz-${_kname}'
PRESETS=('default' 'fallback')
default_image='/boot/initramfs-${_kname}.img'
fallback_image='/boot/initramfs-${_kname}-fallback.img'
fallback_options='-S autodetect'
MKPRESET
        echo "[DC-Arch] ✓ Preset creato: /etc/mkinitcpio.d/${_kname}.preset"
        _created=$((_created + 1))
    done
    [ "$_created" -gt 0 ]
}

_dc_build_mkinitcpio() {
    # Patch fix-34: NON usare mkinitcpio -P né presets.
    # -P scrive in /boot/initramfs-linux.img (path standard) con tutti i
    # drop-in attivi (archiso.conf aggiunge hook PXE non soddisfabili nel clone
    # → missing ipconfig/nbd-client/nfsmount → initramfs incompleto → boot rotto).
    #
    # Approccio corretto:
    #  1. Disabilita temporaneamente il drop-in archiso.conf (PXE hooks)
    #  2. Costruisci SOLO /boot/initramfs-live.img (file dedicato, non tocca il
    #     path standard dei preset)
    #  3. Ripristina il drop-in
    local _kf _kname _drop_in="/etc/mkinitcpio.conf.d/archiso.conf"
    local _drop_bak="/tmp/archiso-dropin.conf.bak"

    # Fix 44: usa sort -V | tail -n1 (stessa logica GRUB step 20) per garantire che
    # initramfs-live.img venga costruito per il kernel che GRUB effettivamente booterà.
    # Con 2 kernel (es. linux-cachyos + linux-cachyos-lts su CachyOS), head -1 prendeva
    # il non-LTS (vmlinuz-linux-cachyos, alfabeticamente primo) ma sort -V | tail -n1
    # prende il LTS (vmlinuz-linux-cachyos-lts ha suffisso -lts > fine stringa).
    # Il mismatch causava: kernel 6.18.20-cachyos-lts + initramfs con moduli 6.19.10-cachyos
    # → modules.devname not found → sr_mod non caricato → CACHYOS_LIVE device not found.
    _kf=$(ls /boot/vmlinuz-linux* 2>/dev/null | grep -v fallback | sort -V | tail -n1)
    [ -z "$_kf" ] && _kf=$(ls /boot/vmlinuz-* 2>/dev/null | grep -v fallback | sort -V | tail -n1)
    if [ -z "$_kf" ] || [ ! -f "$_kf" ]; then
        echo "[DC-Arch] ERROR: nessun vmlinuz-* trovato in /boot"
        return 1
    fi
    _kname=$(basename "$_kf" | sed 's/^vmlinuz-//')
    echo "[DC-Arch] → build live initramfs per kernel: $_kname (Fix 44: sort -V | tail -n1)"

    # Disabilita drop-in archiso.conf per evitare hook PXE (ipconfig/nbd/nfs)
    if [ -f "$_drop_in" ]; then
        mv "$_drop_in" "$_drop_bak"
        echo "[DC-Arch] → drop-in archiso.conf sospeso temporaneamente"
    fi

    # Fix 43 — depmod con kernel version string corretto (non package name)
    # _kname = "linux-cachyos-lts" (package name), depmod -a vuole "6.18.20-1-cachyos-lts"
    # Ricava la version string cercando in /lib/modules/ la dir che matcha il suffisso del pacchetto
    local _kver _ksuffix
    _ksuffix=$(echo "${_kname}" | sed 's/^linux-//')   # "cachyos-lts" oppure "cachyos"
    _kver=$(ls /lib/modules/ 2>/dev/null | grep -F "${_ksuffix}" | sort -V | tail -n1)
    [ -z "${_kver}" ] && _kver=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -n1)
    if [ -n "${_kver}" ] && [ -d "/lib/modules/${_kver}" ]; then
        depmod -a "${_kver}" 2>/dev/null && \
            echo "[DC-Arch] ✓ depmod -a ${_kver}: modules.devname rigenerato" || \
            echo "[DC-Arch] WARN: depmod -a ${_kver} fallito (non bloccante)"
    fi

    # Build dedicato → /boot/initramfs-live.img (NON tocca initramfs-linux.img)
    mkinitcpio \
        -c /etc/mkinitcpio.conf \
        -k "/boot/vmlinuz-${_kname}" \
        -g /boot/initramfs-live.img
    local _rc=$?

    # Ripristina drop-in
    [ -f "$_drop_bak" ] && mv "$_drop_bak" "$_drop_in"

    return $_rc
}

if _ensure_kernel_in_chroot; then
    # BLOCCANTE: se mkinitcpio fallisce il clone ISO non è bootabile
    if ! _dc_build_mkinitcpio; then
        echo "[DC-Arch] ERROR: build initramfs-live.img fallita — clone non bootabile"
        exit 1
    fi
    # Verifica
    if command -v lsinitcpio >/dev/null 2>&1 && [ -f /boot/initramfs-live.img ]; then
        if lsinitcpio /boot/initramfs-live.img 2>/dev/null | grep -q archiso; then
            echo "[DC-Arch] ✓ hook archiso verificato in initramfs-live.img"
        else
            echo "[DC-Arch] WARN: hook archiso NON trovato in initramfs-live.img"
        fi
    fi
    echo "[DC-Arch] ✓ initramfs-live.img: $(du -h /boot/initramfs-live.img 2>/dev/null | cut -f1)"
else
    echo "[DC-Arch] ERROR: kernel non disponibile — impossibile generare initramfs"
    exit 1
fi

# ── Verifica/completa utente live archie ─────────────────────────────────────
# Il cross-distro chroot (step comune) ha già creato archie da zero
# (step [11/30] ha rimosso tutti gli utenti host UID >= 1000).
# Qui ci limitiamo a verificare che archie esista, completare i gruppi
# e scrivere i file di stato usati da remove-live-admin.service.
set +e
[ -f /tmp/dc_env.sh ] && . /tmp/dc_env.sh
_LIVE_PWD="${DC_ROOT_PASSWORD:-root}"
_LIVE_USER="archie"

# Verifica archie esiste; se mancante (anomalia) crealo
if ! id "$_LIVE_USER" &>/dev/null; then
    echo "[DC-Arch] WARN: archie non trovato — creo utente live"
    useradd -m -s /bin/bash -u 1000 -c "Live User" "$_LIVE_USER" 2>/dev/null || \
    useradd -m -s /bin/bash -c "Live User" "$_LIVE_USER" 2>/dev/null
fi
echo "[DC-Arch] ✓ Utente live: $_LIVE_USER (UID=$(id -u $_LIVE_USER 2>/dev/null))"

# Scrivi nome utente live per remove-live-admin.service e dc-post-users
echo "$_LIVE_USER" > /tmp/dc_actual_live_user
echo "$_LIVE_USER" > /etc/distroClone-live-user

# Assicura home directory e shell bash
mkdir -p "/home/${_LIVE_USER}"
chown "${_LIVE_USER}:${_LIVE_USER}" "/home/${_LIVE_USER}" 2>/dev/null || true
# Imposta shell bash (CachyOS usa fish di default, bash più compatibile per live)
usermod -s /bin/bash "$_LIVE_USER" 2>/dev/null || true

# Imposta password
echo "${_LIVE_USER}:${_LIVE_PWD}" | chpasswd 2>/dev/null || true
echo "root:${_LIVE_PWD}" | chpasswd 2>/dev/null || true
echo "[DC-Arch] ✓ Password impostata per $_LIVE_USER e root (pwd: $_LIVE_PWD)"

# Aggiungi ai gruppi (wheel = sudo su Arch)
# autologin: gruppo richiesto da LightDM su Arch per autologin senza password
groupadd -r autologin 2>/dev/null || true
usermod -aG wheel,audio,video,storage,optical,network,power,autologin "$_LIVE_USER" 2>/dev/null || true

# Abilita sudo per gruppo wheel (sudoers)
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers 2>/dev/null || true
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers 2>/dev/null || true
echo "[DC-Arch] ✓ sudo wheel e gruppo autologin abilitati"

# ── Configura autologin per display manager disponibile ──────────────────────
# Rileva la sessione effettivamente installata nel chroot (xsessions + wayland-sessions)
# Priorità: plasma (KDE) > gnome > cinnamon > xfce > mate > prima disponibile
_DM_SESSION=""
for _s in plasma plasmawayland kde-plasma gnome gnome-xorg gnome-wayland cinnamon xfce4 xfce MATE mate; do
    if [ -f "/usr/share/wayland-sessions/${_s}.desktop" ] || \
       [ -f "/usr/share/xsessions/${_s}.desktop" ]; then
        _DM_SESSION="$_s"
        break
    fi
done
# Fallback: prima sessione .desktop trovata
if [ -z "$_DM_SESSION" ]; then
    _first_sess=$(ls /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop 2>/dev/null | head -1)
    [ -n "$_first_sess" ] && _DM_SESSION=$(basename "$_first_sess" .desktop)
fi
# Ultimo fallback: plasma (CachyOS/Arch KDE default)
[ -z "$_DM_SESSION" ] && _DM_SESSION="plasma"
echo "[DC-Arch] Sessione rilevata per autologin: $_DM_SESSION"

if [ -f /etc/lightdm/lightdm.conf ]; then
    # LightDM: richiede [Seat:*] con autologin-user e autologin-session
    # Rimuovi righe autologin preesistenti e riscrivi pulite
    sed -i '/^#\?autologin-user=/d;/^#\?autologin-user-timeout=/d;/^#\?autologin-session=/d' \
        /etc/lightdm/lightdm.conf 2>/dev/null || true
    if grep -q '^\[Seat:\*\]' /etc/lightdm/lightdm.conf; then
        sed -i "/^\[Seat:\*\]/a autologin-session=${_DM_SESSION}\nautologin-user-timeout=0\nautologin-user=${_LIVE_USER}" \
            /etc/lightdm/lightdm.conf
    else
        printf '\n[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\nautologin-session=%s\n' \
            "$_LIVE_USER" "$_DM_SESSION" >> /etc/lightdm/lightdm.conf
    fi
    echo "[DC-Arch] ✓ autologin LightDM: utente=$_LIVE_USER sessione=$_DM_SESSION"
elif command -v sddm >/dev/null 2>&1 || [ -d /etc/sddm.conf.d ]; then
    # SDDM: Session usa nome senza .desktop
    mkdir -p /etc/sddm.conf.d
    printf '[Autologin]\nUser=%s\nSession=%s\n' "$_LIVE_USER" "$_DM_SESSION" \
        > /etc/sddm.conf.d/autologin.conf
    echo "[DC-Arch] ✓ autologin SDDM: utente=$_LIVE_USER sessione=$_DM_SESSION"
elif [ -d /etc/gdm ] || [ -d /etc/gdm3 ]; then
    _GDM_DIR="/etc/gdm"; [ -d /etc/gdm3 ] && _GDM_DIR="/etc/gdm3"
    mkdir -p "$_GDM_DIR"
    cat > "$_GDM_DIR/custom.conf" << GDMCONF
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=$_LIVE_USER
TimedLoginEnable=False

[security]

[xdmcp]

[chooser]
GDMCONF
    echo "[DC-Arch] ✓ autologin GDM: utente=$_LIVE_USER"
else
    echo "[DC-Arch] ⚠ Display manager non rilevato — autologin non configurato"
fi

# ── Nascondi live user dal greeter nel sistema installato ────────────────────
# Doppio meccanismo (defense-in-depth):
#   1. AccountsService SystemAccount=true → nascosto da SDDM/GDM/LightDM
#   2. SDDM HideUsers=archie  → rinforzo specifico per SDDM (EOS/Garuda/Manjaro)
# Nella live: autologin bypassa il greeter → archie non viene mai mostrato.
# Nel target: dc-post-users.sh (Calamares, pacman-gated) rimuove archie durante
#   l'installazione → primo avvio già pulito.
# remove-live-admin.service = safety net (rimuove archie se dc-post-users fallisce).
mkdir -p /var/lib/AccountsService/users
printf '[User]\nSystemAccount=true\n' > "/var/lib/AccountsService/users/${_LIVE_USER}"
chmod 644 "/var/lib/AccountsService/users/${_LIVE_USER}"
echo "[DC-Arch] ✓ AccountsService: ${_LIVE_USER} marcato SystemAccount=true (nascosto da greeter nel target)"

# SDDM HideUsers (rinforzo esplicito per EOS/Garuda/Manjaro con SDDM)
if command -v sddm >/dev/null 2>&1 || [ -d /etc/sddm.conf.d ]; then
    mkdir -p /etc/sddm.conf.d
    printf '[Users]\nHideUsers=%s\n' "$_LIVE_USER" \
        > /etc/sddm.conf.d/dc-hide-live-user.conf
    chmod 644 /etc/sddm.conf.d/dc-hide-live-user.conf
    echo "[DC-Arch] ✓ SDDM HideUsers: ${_LIVE_USER} nascosto da greeter nel target"
fi

# Verifica finale utente
echo "[DC-Arch] Verifica utente in passwd:"
grep "^${_LIVE_USER}:" /etc/passwd || echo "[DC-Arch] WARN: ${_LIVE_USER} non in passwd!"
echo "[DC-Arch] Verifica utente in shadow:"
grep "^${_LIVE_USER}:" /etc/shadow | sed 's/:[^:]*:/:HASH:/' || \
    echo "[DC-Arch] WARN: ${_LIVE_USER} non in shadow!"

# ── Hostname ─────────────────────────────────────────────────────────────────
_DC_HOST="${DC_HOSTNAME:-${DC_DISTRO_ID:-arch}-live}"
echo "$_DC_HOST" > /etc/hostname
# Aggiorna /etc/hosts con il nuovo hostname
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${_DC_HOST}/" /etc/hosts 2>/dev/null || \
    echo -e "127.0.1.1\t${_DC_HOST}" >> /etc/hosts
echo "[DC-Arch] ✓ hostname impostato: $_DC_HOST"

# ── calamares-config.sh: configura branding e moduli Calamares per Arch ──────
if [ -f /tmp/calamares-config.sh ]; then
    _CC_FAM="arch"
    _CC_DIST="arch"
    _CC_BRAND="distroClone"
    [ -f /tmp/dc_calamares_args ] && {
        _CC_FAM=$(sed -n '1p' /tmp/dc_calamares_args)
        _CC_DIST=$(sed -n '2p' /tmp/dc_calamares_args)
        _CC_BRAND=$(sed -n '3p' /tmp/dc_calamares_args)
    }
    bash /tmp/calamares-config.sh "$_CC_FAM" "$_CC_DIST" "$_CC_BRAND" && \
        echo "[DC-Arch] ✓ calamares-config.sh completato (brand=$_CC_BRAND)" || \
        echo "[DC-Arch] ⚠ calamares-config.sh fallito — configurazione manuale"
    rm -f /tmp/calamares-config.sh /tmp/dc_calamares_args 2>/dev/null || true
fi

# ── Calamares branding: Arch usa /usr/share/calamares/settings*.conf ─────────
# Su CachyOS il pacchetto calamares-cachyos mette settings.conf in /usr/share/,
# non in /etc/calamares/ → copiamo e aggiorniamo il branding
mkdir -p /etc/calamares
if [ ! -f /etc/calamares/settings.conf ]; then
    # Preferisci settings_online.conf se esiste (CachyOS)
    if [ -f /usr/share/calamares/settings_online.conf ]; then
        cp /usr/share/calamares/settings_online.conf /etc/calamares/settings.conf
        echo "[DC-Arch] → settings.conf copiato da settings_online.conf"
    elif [ -f /usr/share/calamares/settings.conf ]; then
        cp /usr/share/calamares/settings.conf /etc/calamares/settings.conf
        echo "[DC-Arch] → settings.conf copiato da /usr/share/calamares/"
    fi
fi
# Aggiorna branding in tutti i settings.conf accessibili
for _sf in /etc/calamares/settings.conf \
           /usr/share/calamares/settings.conf \
           /usr/share/calamares/settings_online.conf \
           /usr/share/calamares/settings_offline.conf; do
    [ -f "$_sf" ] && sed -i 's/^branding:.*$/branding: distroClone/' "$_sf"
done
echo "[DC-Arch] ✓ branding: distroClone impostato in settings.conf"

# ── sudoers NOPASSWD per calamares ────────────────────────────────────────────
# Su Arch pkexec richiede un polkit agent non garantito → sudo NOPASSWD
mkdir -p /etc/sudoers.d
# SETENV: permette a sudo -E di preservare DISPLAY/XAUTHORITY/QT_*
echo "${_LIVE_USER} ALL=(ALL) NOPASSWD: SETENV: /usr/bin/calamares" \
    > /etc/sudoers.d/distroClone-calamares
chmod 440 /etc/sudoers.d/distroClone-calamares
echo "[DC-Arch] ✓ sudoers NOPASSWD+SETENV calamares per ${_LIVE_USER}"

# ── calamares-launcher: sudo NOPASSWD (Arch/CachyOS) ────────────────────────
# sudo -E ha priorità: la regola NOPASSWD in sudoers.d è già impostata sopra.
# pkexec come fallback: richiede polkit agent attivo, altrimenti chiede password.
# env DISPLAY/XAUTHORITY preservati in entrambi i casi.
cat > /usr/local/bin/calamares-launcher << 'CALWRAP'
#!/bin/bash
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
if [ ! -f "$XAUTHORITY" ]; then
    _DU=$(who | awk 'NR==1{print $1}')
    _AUTH=$(find "/home/${_DU}/.Xauthority" /run/user/*/gdm/Xauthority \
        /tmp/.gdm-xauth* 2>/dev/null | head -1)
    [ -f "$_AUTH" ] && export XAUTHORITY="$_AUTH"
fi
# sudo -E prima: la regola sudoers NOPASSWD è già impostata per calamares
# pkexec come fallback (potrebbe chiedere password se polkit agent non attivo)
if command -v sudo >/dev/null 2>&1; then
    exec sudo -E /usr/bin/calamares "$@"
else
    exec pkexec env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" /usr/bin/calamares "$@"
fi
CALWRAP
chmod 755 /usr/local/bin/calamares-launcher
echo "[DC-Arch] ✓ calamares-launcher creato (sudo NOPASSWD / fallback pkexec)"

# ── Moduli calamares: keyboard.conf per evitare crash applyXkb ───────────────
# Bug: Calamares crasha con Bus error in applyXkb quando variant=""
# Fix: fornire keyboard.conf con valori espliciti non vuoti
mkdir -p /etc/calamares/modules
cat > /etc/calamares/modules/keyboard.conf << 'KBCONF'
---
# DistroClone: keyboard module config
# Evita crash applyXkb con variant vuota
xkbLayout:  "us"
xkbVariant: ""
xkbOptions: ""
xkbModel:   "pc105"
KBCONF

# ── unpackfs.conf: squashfs in archiso path (tutti i sistemi Arch) ───────────
# archiso monta ISO in /run/archiso/bootmnt → squashfs in arch/<arch>/airootfs.sfs
# IMPORTANTE: preserva la lista exclude da calamares-config.sh
_ARCH_LIVE_USER=$(cat /etc/distroClone-live-user 2>/dev/null | tr -d '[:space:]')
[ -z "$_ARCH_LIVE_USER" ] && _ARCH_LIVE_USER="archie"
_ARCH=$(uname -m)
_UNPACK_SOURCE="/run/archiso/bootmnt/arch/${_ARCH}/airootfs.sfs"
cat > /etc/calamares/modules/unpackfs.conf << UPCFS
---
unpack:
  - source: ${_UNPACK_SOURCE}
    sourcefs: squashfs
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
      - /var/lib/pacman/sync/*
      - /var/cache/pacman/pkg/*
      - /var/log/*
      - /var/tmp/*
      - /swapfile
      - /home/${_ARCH_LIVE_USER}/*
UPCFS
echo "[DC-Arch] ✓ unpackfs.conf → ${_UNPACK_SOURCE}"

# Crea anche localecfg.conf se mancante (warning frequente)
[ -f /etc/calamares/modules/localecfg.conf ] || \
cat > /etc/calamares/modules/localecfg.conf << 'LCCONF'
---
# DistroClone: minimal localecfg
LCCONF

# ── shellprocess: crea /tmp nel target PRIMA di mkinitcpio ───────────────────
# Calamares esegue shellprocess sull'host; usiamo il mountpoint del target
# che Calamares espone come /tmp/calamares-root (o simile) via GlobalStorage
# Alternativa sicura: script che crea /tmp dentro il target via path assoluto
cat > /etc/calamares/modules/shellprocess_premkinitcpio.conf << 'SPCFS'
---
# Crea /tmp nel target prima di mkinitcpio
# Calamares sostituisce @@{RootMountPoint}@@ con il mountpoint reale
script:
  - "-/bin/bash -c 'MP=$(cat /tmp/calamares-root 2>/dev/null || echo /tmp/calamares-root); [ -d \"$MP\" ] && mkdir -p \"$MP/tmp\" && chmod 1777 \"$MP/tmp\" || true'"
SPCFS

# umount.conf e finished.conf minimali (evitano warning all'avvio)
[ -f /etc/calamares/modules/umount.conf ] || \
    echo '---' > /etc/calamares/modules/umount.conf
[ -f /etc/calamares/modules/finished.conf ] || \
cat > /etc/calamares/modules/finished.conf << 'FINCONF'
---
restartNowEnabled: true
restartNowChecked: false
restartNowCommand: "reboot"
FINCONF
echo "[DC-Arch] ✓ moduli calamares configurati (keyboard, localecfg, umount, finished)"

# ── Icona distroClone: cerca nel branding, copia in pixmaps ──────────────────
_DC_ICON="calamares"
for _ico in \
    "/usr/share/calamares/branding/distroClone/distroClone-installer.png" \
    "/usr/share/calamares/branding/distroClone/distroClone-logo.png" \
    "/usr/share/calamares/branding/distroClone/logo.png" \
    "/usr/share/icons/hicolor/256x256/apps/distroClone.png" \
    "/usr/share/icons/hicolor/128x128/apps/distroClone.png" \
    "/usr/share/icons/hicolor/48x48/apps/distroClone.png" \
    "/usr/share/pixmaps/distroClone.png"; do
    if [ -f "$_ico" ]; then
        mkdir -p /usr/share/pixmaps
        cp "$_ico" /usr/share/pixmaps/distroClone.png
        _DC_ICON=/usr/share/pixmaps/distroClone.png
        echo "[DC-Arch] ✓ icona distroClone copiata da $_ico"
        break
    fi
done
[ "$_DC_ICON" = "calamares" ] && echo "[DC-Arch] ⚠ icona distroClone non trovata, uso fallback calamares"

# ── .desktop voce menu + icona Desktop ───────────────────────────────────────
# Scrive il .desktop con icona e path risolti (sed su variabile espansa)
_DS=/usr/share/applications/install-system.desktop
printf '[Desktop Entry]\nType=Application\nName=Install System\nComment=Install this system to disk\nExec=/usr/local/bin/calamares-launcher\nIcon=%s\nTerminal=false\nCategories=System;Installer;\nStartupNotify=true\nX-Caja-No-Confirm=true\n' "$_DC_ICON" > "$_DS"
chmod 644 "$_DS"

# Copia icona sul Desktop dell'utente live, già con il trust flag via xattr
mkdir -p "/home/${_LIVE_USER}/Desktop"
install -Dm755 "$_DS" "/home/${_LIVE_USER}/Desktop/install-system.desktop"
# Imposta xattr trusted (funziona solo se filesystem supporta xattr, tentativo)
setfattr -n user.metadata::trusted -v "yes" \
    "/home/${_LIVE_USER}/Desktop/install-system.desktop" 2>/dev/null || true
chown -R "${_LIVE_USER}:${_LIVE_USER}" "/home/${_LIVE_USER}/Desktop"
echo "[DC-Arch] ✓ icona Install System su Desktop di ${_LIVE_USER} (icon: ${_DC_ICON})"

# Rimuovi il .desktop stock del pacchetto calamares
# Il pacchetto installa calamares.desktop (e varianti) in /usr/share/applications/
# → rimane solo install-system.desktop con branding DC
for _cal_dt in \
    /usr/share/applications/calamares.desktop \
    /usr/share/applications/io.calamares.calamares.desktop \
    /usr/share/applications/calamares-install.desktop \
    "/home/${_LIVE_USER}/Desktop/calamares.desktop" \
    "/home/${_LIVE_USER}/Desktop/io.calamares.calamares.desktop" \
    /root/Desktop/calamares.desktop \
    /etc/skel/Desktop/calamares.desktop; do
    rm -f "$_cal_dt" 2>/dev/null || true
done
echo "[DC-Arch] ✓ rimossi .desktop stock calamares (resta solo install-system.desktop)"

# Aggiorna database .desktop
update-desktop-database /usr/share/applications 2>/dev/null || true

# ── Trust launcher .desktop su MATE (Caja non esegue file senza trusted flag) ─
# Metodo 1: xattr user.trusted (funziona su filesystems con user_xattr)
for _dt in \
    "/home/${_LIVE_USER}/Desktop/install-system.desktop" \
    "/usr/share/applications/install-system.desktop"; do
    [ -f "$_dt" ] || continue
    # Imposta attributo xattr per Caja/Nautilus
    setfattr -n user.trusted -v "yes" "$_dt" 2>/dev/null || true
    # Metodo 2: gio set (GNOME/Caja utility)
    gio set "$_dt" metadata::trusted true 2>/dev/null || true
done

# Metodo 3: autostart script che imposta trusted al primo avvio utente
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/dc-trust-launchers.desktop << 'TRSTDT'
[Desktop Entry]
Type=Application
Name=Trust DC Launchers
Exec=/bin/bash -c 'sleep 2; for f in "$HOME/Desktop"/*.desktop; do gio set "$f" metadata::trusted true 2>/dev/null; chmod +x "$f" 2>/dev/null; done'
NoDisplay=true
X-GNOME-Autostart-enabled=true
OnlyShowIn=MATE;GNOME;XFCE;
TRSTDT
echo "[DC-Arch] ✓ trust launcher impostato per MATE/Caja"

# ── Autostart: marca .desktop come trusted per Caja (MATE file manager) ──────
# Caja richiede metadata::trusted per eseguire .desktop senza dialogo Trust.
# gio set non funziona nel chroot (nessun D-Bus), quindi usiamo un autostart
# che gira al primo login e imposta il flag.
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/dc-trust-desktop.desktop << 'TRUST_EOF'
[Desktop Entry]
Type=Application
Name=Trust DistroClone Desktop Launcher
Exec=/bin/bash -c 'sleep 3; for f in "$HOME/Desktop/install-system.desktop"; do [ -f "$f" ] && chmod +x "$f" && gio set "$f" metadata::trusted true 2>/dev/null && caja-trust "$f" 2>/dev/null; done'
NoDisplay=true
X-MATE-Autostart-enabled=true
X-GNOME-Autostart-enabled=true
OnlyShowIn=MATE;GNOME;
TRUST_EOF
echo "[DC-Arch] ✓ autostart trust desktop creato"

# ── Disabilita servizi live Arch/CachyOS nel squashfs ────────────────────────
# Questi servizi (archiso, CachyOS live) sono ABILITATI nel live system.
# Vengono copiati nel sistema installato dal squashfs.
# Se non disabilitati qui, girano al primo boot del sistema installato
# e fanno cleanup aggressivo: userdel, rm /home, ecc.
set +e
for _LIVE_SVC in \
    cachyos-live.service \
    cachyos-firstboot.service \
    cachyos-configure-after-reboot.service \
    garuda-firstrun.service \
    garuda-setup-assistant.service \
    garuda-live.service \
    archiso-reconfiguration.service \
    archiso-keyring-populate.service \
    archiso-copy-passwd.service \
    archiso.service \
    pacman-init.service \
    clean-live.service \
    livesys.service \
    livesys-late.service; do
    systemctl disable "$_LIVE_SVC" 2>/dev/null && \
        echo "[DC-Arch] ✓ disabilitato servizio live: $_LIVE_SVC" || true
    # Rimuovi anche il symlink da multi-user.target.wants se presente
    rm -f "/etc/systemd/system/multi-user.target.wants/${_LIVE_SVC}" 2>/dev/null || true
    rm -f "/etc/systemd/system/graphical.target.wants/${_LIVE_SVC}" 2>/dev/null || true
done

# ── Discovery aggressiva: trova e disabilita QUALSIASI servizio live ──────
# Non ci fidiamo di una lista statica — cerchiamo per keyword nel nome
echo "[DC-Arch] → Scan servizi abilitati per keyword live/archiso/cachyos..."
_DC_SVC_LOG="/var/log/dc-disabled-services.log"
echo "=== Servizi disabilitati da DistroClone $(date) ===" > "$_DC_SVC_LOG"
for _SVC_FILE in /etc/systemd/system/*.wants/*.service \
                 /etc/systemd/system/*.service \
                 /usr/lib/systemd/system/*.service; do
    [ -e "$_SVC_FILE" ] || continue
    _SVC_NAME=$(basename "$_SVC_FILE")
    # NOTA: NON aggiungere pattern troppo generici (es. *btrfs*, *snap*). Servizi
    # come grub-btrfsd.service (grub-btrfs GRUB snapshot menu) DEVONO sopravvivere
    # al sistema installato — vengono abilitati da dc-firstboot su Arch family.
    case "$_SVC_NAME" in
        *cachyos*|*garuda*|*archiso*|*live-*|*-live.*|clean-live*|pacman-init*|livesys*)
            systemctl disable "$_SVC_NAME" 2>/dev/null && \
                echo "  DISABLED: $_SVC_NAME" | tee -a "$_DC_SVC_LOG"
            rm -f /etc/systemd/system/*.wants/"$_SVC_NAME" 2>/dev/null || true
            ;;
    esac
done

# ── Dump COMPLETO dei servizi abilitati nel log (diagnostica) ─────────────
echo "" >> "$_DC_SVC_LOG"
echo "=== Tutti i servizi abilitati nel squashfs ===" >> "$_DC_SVC_LOG"
systemctl list-unit-files --state=enabled 2>/dev/null >> "$_DC_SVC_LOG"
echo "[DC-Arch] ✓ Log servizi: $_DC_SVC_LOG"

echo "[DC-Arch] ✓ Servizi live Arch/CachyOS disabilitati nel squashfs"

# ── Abilita udisks2 e polkit nel live system ─────────────────────────────
# Calamares partition module usa kpmcore che si connette a udisks2 via D-Bus.
# Senza udisks2 attivo, kpmcore va in timeout D-Bus (~80s) alla schermata
# Welcome prima di caricare il modulo partition.
for _SVC in udisks2 polkit; do
    if systemctl list-unit-files "${_SVC}.service" 2>/dev/null | grep -q "${_SVC}"; then
        systemctl enable "${_SVC}.service" 2>/dev/null && \
            echo "[DC-Arch] ✓ ${_SVC}.service abilitato (kpmcore D-Bus)" || \
            echo "[DC-Arch] WARN: ${_SVC}.service non abilitabile"
    else
        echo "[DC-Arch] WARN: ${_SVC}.service non trovato"
    fi
done

# ── Fix /tmp/.X11-unix ownership (CachyOS GNOME Wayland crash) ──────────────
# Bug: su CachyOS al primo boot /tmp/.X11-unix ha ownership errata → XWayland
# rifiuta di creare socket → gnome-shell SIGABRT → gnome-session muore →
# GdmSessionWorker: "Session never registered, failing" → utente vede GDM
# che rifiuta il login come se la password fosse sbagliata (TTY funziona
# perché non usa X/Wayland).
# Fix: tmpfiles.d drop-in con prefisso 'zz-' (ultima priorità, vince sui
# vendor files). systemd-tmpfiles-setup.service gira PRIMA di
# display-manager.service → /tmp/.X11-unix è corretto quando GDM parte.
# Invariante: 1777 root:root è la policy standard Linux — nessuna regressione
# su Arch/Garuda/EOS/Manjaro che già hanno questo layout.
mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/zz-dc-x11-unix.conf << 'X11TMP'
# DistroClone: forza ownership corretta su /tmp/.X11-unix.
# Necessario su CachyOS dove al primo boot la dir viene pre-creata con
# owner errato causando gnome-shell crash su Wayland.
d /tmp/.X11-unix 1777 root root 10d
X11TMP
echo "[DC-Arch] ✓ tmpfiles.d drop-in /tmp/.X11-unix (fix gnome-shell Wayland)"

# ── Layer 2: dc-x11-unix-enforce.service — EVERY boot, right before DM ──────
# Evidenza 2026-04-18: su CachyOS post-aggiornamenti, tmpfiles-setup crea la
# dir a T0 (1777 root:root), ma a T0+10s qualcosa (gdm-greeter/xwayland/hook
# CachyOS) la ricrea con ownership gdm-greeter:gdm mode 1755 → gnome-shell
# crash su Wayland → "Session never registered" → GDM rifiuta pwd.
# Il fix tmpfiles.d da solo non basta: serve enforcement a runtime, tra
# systemd-tmpfiles-setup.service e display-manager.service.
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/dc-x11-unix-enforce.service << 'X11SVC'
[Unit]
Description=DistroClone: enforce /tmp/.X11-unix ownership before display manager
Documentation=man:tmpfiles.d(5)
After=systemd-tmpfiles-setup.service local-fs.target
Before=display-manager.service gdm.service lightdm.service sddm.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'mkdir -p /tmp/.X11-unix && chown root:root /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
X11SVC
# Enable via manual symlink (mai systemctl in chroot)
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/dc-x11-unix-enforce.service \
       /etc/systemd/system/multi-user.target.wants/dc-x11-unix-enforce.service
echo "[DC-Arch] ✓ dc-x11-unix-enforce.service installato (layer runtime anti-XWayland crash)"
set -e

CHROOT_ARCH_EOF
    ;; # fine case arch

  # ════════════════════════════════════════════════════════════════════════════
  # FEDORA / OPENSUSE FAMILY — usa dracut-live al posto di live-boot
  # openSUSE usa la stessa struttura Fedora: dracut + grub2 + zypper
  # ════════════════════════════════════════════════════════════════════════════
  fedora|opensuse)
# ── Pre-chroot: assicura resolv.conf funzionante per dnf nel chroot ──────────
# Fedora usa systemd-resolved: /etc/resolv.conf → /run/systemd/resolve/stub-resolv.conf
if [ ! -f "$DEST/etc/resolv.conf" ] || [ ! -s "$DEST/etc/resolv.conf" ]; then
    echo "[DC-Fedora] Copio resolv.conf per dnf nel chroot..."
    cp /etc/resolv.conf "$DEST/etc/resolv.conf" 2>/dev/null ||         echo "nameserver 8.8.8.8" > "$DEST/etc/resolv.conf"
fi
echo "[DC-Fedora] resolv.conf: $(cat $DEST/etc/resolv.conf | head -2)"

    chroot "$DEST" /bin/bash << 'CHROOT_FEDORA_EOF'
set +e
# Carica variabili dall'host (DC_FAMILY, DC_LIVE_USER, DC_ROOT_PASSWORD)
[ -f /tmp/dc_env.sh ] && . /tmp/dc_env.sh
# Inizializza _LU subito (usato in tutti i blocchi seguenti)
_LU="${DC_LIVE_USER:-liveuser}"

# ── Hostname ──────────────────────────────────────────────────────────────────
# openSUSE spesso non ha /etc/hostname (usa solo hostnamectl/systemd-hostnamed),
# quindi rsync porta un file vuoto → live mostra "localhost". Scriviamo sempre.
_DC_HOST="${DC_HOSTNAME:-${DC_DISTRO_ID:-opensuse}-live}"
echo "$_DC_HOST" > /etc/hostname
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${_DC_HOST}/" /etc/hosts 2>/dev/null || \
    echo -e "127.0.1.1\t${_DC_HOST}" >> /etc/hosts
echo "[DC-Fedora] ✓ hostname impostato: $_DC_HOST"

# ── Rimuovi wizard primo avvio e installer default ────────────────────────────
echo "[DC-Fedora] Rimozione wizard primo avvio (famiglia: ${DC_FAMILY:-fedora})..."
if command -v dnf >/dev/null 2>&1; then
    dnf remove -y gnome-initial-setup 2>/dev/null || true
    dnf remove -y anaconda anaconda-core anaconda-gui anaconda-tui anaconda-utils \
        anaconda-widgets liveinst 2>/dev/null || true
elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive remove -y gnome-initial-setup 2>/dev/null || true
fi
rm -f /usr/share/applications/gnome-initial-setup.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/gnome-initial-setup-first-login.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/gnome-initial-setup-copy-worker.desktop 2>/dev/null || true
rm -f /usr/share/applications/liveinst.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/liveinst-setup.desktop 2>/dev/null || true
echo "[DC-Fedora] ✓ wizard primo avvio rimosso"

# ── Autologin display manager ─────────────────────────────────────────────────
echo "[DC-Fedora] Configurazione autologin per ${_LU}..."
# Rileva sessione disponibile (plasma/gnome/xfce/...)
_DM_SESSION=""
for _s in plasma plasmawayland kde-plasma gnome gnome-xorg gnome-wayland cinnamon xfce4 xfce MATE mate; do
    if [ -f "/usr/share/wayland-sessions/${_s}.desktop" ] || \
       [ -f "/usr/share/xsessions/${_s}.desktop" ]; then
        _DM_SESSION="$_s"
        break
    fi
done
[ -z "$_DM_SESSION" ] && _DM_SESSION="plasma"
echo "[DC-Fedora] Sessione per autologin: $_DM_SESSION"

# SDDM (openSUSE Plasma, Fedora KDE)
if command -v sddm >/dev/null 2>&1 || [ -d /etc/sddm.conf.d ]; then
    mkdir -p /etc/sddm.conf.d
    printf '[Autologin]\nUser=%s\nSession=%s\n' "$_LU" "$_DM_SESSION" \
        > /etc/sddm.conf.d/autologin.conf
    echo "[DC-Fedora] ✓ autologin SDDM: utente=$_LU sessione=$_DM_SESSION"
fi
# GDM (Fedora GNOME, openSUSE GNOME)
if [ -d /etc/gdm ] || [ -d /etc/gdm3 ]; then
    _GDM_DIR="/etc/gdm"; [ -d /etc/gdm3 ] && _GDM_DIR="/etc/gdm3"
    mkdir -p "$_GDM_DIR"
    cat > "$_GDM_DIR/custom.conf" << GDMCONF
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=${_LU}
TimedLoginEnable=False

[security]

[xdmcp]

[chooser]

[debug]
GDMCONF
    echo "[DC-Fedora] ✓ autologin GDM: utente=$_LU"
elif ! command -v sddm >/dev/null 2>&1 && [ ! -d /etc/sddm.conf.d ]; then
    # Nessun DM rilevato — crea GDM di default
    mkdir -p /etc/gdm
    cat > /etc/gdm/custom.conf << GDMCONF2
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=${_LU}
TimedLoginEnable=False
GDMCONF2
    echo "[DC-Fedora] ✓ autologin GDM (creato): utente=$_LU"
fi
echo "[DC-Fedora] ✓ autologin configurato per $_LU"

# ── Crea utente liveuser ─────────────────────────────────────────────────────
# DC_ROOT_PASSWORD e DC_LIVE_USER caricati da dc_env.sh sopra
_LU="${DC_LIVE_USER:-liveuser}"
_LP="${DC_ROOT_PASSWORD:-liveuser}"
echo "[DC-Fedora] Creazione utente $_LU (password: $_LP)..."

# Controlla se esiste già un utente con UID 1000 (utente host clonato)
_OLD_UID1000=$(awk -F: '$3==1000{print $1}' /etc/passwd 2>/dev/null | head -1)
if [ -n "$_OLD_UID1000" ] && [ "$_OLD_UID1000" != "$_LU" ]; then
    echo "[DC-Fedora] UID 1000 occupato da $_OLD_UID1000 → rinomino in $_LU"
    usermod -l "$_LU" "$_OLD_UID1000" 2>/dev/null &&         usermod -d "/home/$_LU" -m "$_LU" 2>/dev/null || {
            # usermod fallito: rimuovi e ricrea
            userdel -r "$_OLD_UID1000" 2>/dev/null || true
            useradd -m -s /bin/bash -u 1000 -c "Live User" "$_LU" 2>/dev/null ||             useradd -m -s /bin/bash -c "Live User" "$_LU"
        }
elif ! id "$_LU" &>/dev/null; then
    useradd -m -s /bin/bash -u 1000 -c "Live User" "$_LU" 2>/dev/null ||     useradd -m -s /bin/bash -c "Live User" "$_LU"
fi

# Imposta password — tre metodi in cascata per massima compatibilità chroot
if id "$_LU" &>/dev/null; then
    # Metodo 1: usermod -p con hash openssl (funziona sempre in chroot)
    _HASH=$(openssl passwd -6 "$_LP" 2>/dev/null)
    if [ -n "$_HASH" ]; then
        usermod -p "$_HASH" "$_LU"
        usermod -p "$_HASH" root 2>/dev/null || true
        echo "[DC-Fedora] ✓ password impostata via openssl hash"
    else
        # Metodo 2: passwd --stdin
        echo "$_LP" | passwd --stdin "$_LU" 2>/dev/null ||             echo "$_LP" | passwd --stdin root 2>/dev/null || true
        echo "[DC-Fedora] ✓ password impostata via passwd --stdin"
    fi
    usermod -aG wheel,audio,video,dialout,cdrom,plugdev,netdev "$_LU" 2>/dev/null || true
    echo "[DC-Fedora] ✓ utente $_LU pronto | password: $_LP | sudo: NOPASSWD"
else
    echo "[DC-Fedora] ✗ ERRORE CRITICO: impossibile creare utente $_LU"
fi

# ── Configura sudo NOPASSWD+SETENV per liveuser (sudo -E calamares) ──────────
mkdir -p /etc/sudoers.d
printf '%s ALL=(ALL) NOPASSWD: SETENV: ALL\n' "$_LU" > /etc/sudoers.d/distroClone-calamares
chmod 440 /etc/sudoers.d/distroClone-calamares
# Rimuovi eventuale regola liveuser residua per evitare conflitti
rm -f /etc/sudoers.d/liveuser 2>/dev/null || true
echo "[DC-Fedora] ✓ sudo NOPASSWD+SETENV per $_LU (calamares-launcher)"

# ── Installa/reinstalla calamares e dipendenze ────────────────────────────────
echo "[DC-Fedora] Reinstallazione calamares e yad (famiglia: ${DC_FAMILY:-fedora})..."
if command -v dnf >/dev/null 2>&1; then
    dnf makecache -y 2>/dev/null || true
    dnf reinstall -y yad 2>&1 | tail -5 || \
        dnf install -y yad 2>&1 | tail -5 || true
    dnf install -y xcb-util-cursor libxcb xcb-util qt6-qtbase \
        qt6-qtdeclarative qt6-qtsvg 2>&1 | tail -5 || true
elif command -v zypper >/dev/null 2>&1; then
    # openSUSE: calamares dal repo custom home:carluad:greemond (installato in pre-chroot HOST)
    # Il calamares custom include partition.so Qt6; il nativo Tumbleweed non lo include.
    _DC_CAL_REPO_NAME="home_carluad_greemond"
    _DC_CAL_REPO_URL="https://download.opensuse.org/repositories/home:carluad:greemond/standard/home:carluad:greemond.repo"

    # ── Packman: necessario per yad ──────────────────────────────────────────
    if ! zypper lr 2>/dev/null | grep -qi packman; then
        echo "[DC-openSUSE] Aggiunta repo Packman (richiesto per yad)..."
        if grep -qi tumbleweed /etc/os-release 2>/dev/null; then
            _PM_URL="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/"
        else
            _PM_VER=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release 2>/dev/null || echo "")
            _PM_URL="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Leap_${_PM_VER}/"
        fi
        zypper ar -cfp 90 "$_PM_URL" packman 2>/dev/null || true
        zypper --non-interactive --gpg-auto-import-keys refresh packman 2>/dev/null || true
        echo "[DC-openSUSE] ✓ Packman: $_PM_URL"
    fi

    # ── Repo custom home:carluad:greemond (priorità 50 > OSS 99) ─────────────
    _DC_CAL_REPO_FILE_URL="https://download.opensuse.org/repositories/home:carluad:greemond/standard/home:carluad:greemond.repo"
    while IFS= read -r _old; do
        [ -n "$_old" ] && zypper --non-interactive removerepo "$_old" 2>/dev/null
    done < <(zypper lr 2>/dev/null | awk -F'|' '/greemond/{gsub(/[[:space:]]/,"",$2); print $2}')
    zypper --non-interactive addrepo "$_DC_CAL_REPO_FILE_URL" 2>&1 | tail -3
    zypper --non-interactive --gpg-auto-import-keys refresh 2>/dev/null || true
    _DC_CAL_REPO_NAME=$(zypper lr 2>/dev/null | \
        awk -F'|' '/greemond/{gsub(/[[:space:]]/,"",$2); print $2; exit}')
    [ -n "$_DC_CAL_REPO_NAME" ] && \
        zypper --non-interactive modifyrepo --priority 50 \
            "$_DC_CAL_REPO_NAME" 2>/dev/null

    # ── Dipendenza libyaml-cpp0_8 ─────────────────────────────────────────────
    if ! rpm -q libyaml-cpp0_8 >/dev/null 2>&1; then
        echo "[DC-openSUSE] Download libyaml-cpp0_8 nel target..."
        _DC_YAML_RPM="/tmp/dc-libyaml-cpp0_8-$$.rpm"
        curl -fsSL --retry 2 --connect-timeout 20 \
            "https://rpmfind.net/linux/opensuse/distribution/leap/16.0/repo/oss/x86_64/libyaml-cpp0_8-0.8.0-160000.2.2.x86_64.rpm" \
            -o "$_DC_YAML_RPM" 2>/dev/null && \
            rpm -ivh --nodeps "$_DC_YAML_RPM" 2>&1 | tail -5 || true
        rm -f "$_DC_YAML_RPM"
    fi

    # ── Rimuovi calamares nativo e installa dal repo custom ───────────────────
    zypper --non-interactive refresh 2>/dev/null || true
    # Controlla versione installata: rsync da HOST (3.4) può averla già aggiornata
    _CAL_INST_MAJ=$(rpm -q calamares --qf '%{VERSION}' 2>/dev/null | cut -d. -f1,2)
    echo "[DC-openSUSE] Calamares presente nel target: ${_CAL_INST_MAJ:-nessuno}"
    if echo "$_CAL_INST_MAJ" | grep -q "^3\.2\|^3\.1\|^3\.0\|^2\."; then
        # Versione obsoleta (3.2.x) — rimuovi e installa 3.4 dal repo custom
        echo "[DC-openSUSE] Versione obsoleta (${_CAL_INST_MAJ}) — aggiornamento a 3.4..."
        zypper --non-interactive remove -y calamares 2>&1 | tail -5 || true
        if [ -f /tmp/dc-calamares-custom.rpm ]; then
            echo "[DC-openSUSE] Uso RPM locale (pre-copiato da HOST): $(basename /tmp/dc-calamares-custom.rpm)"
            rpm -Uvh --nodeps /tmp/dc-calamares-custom.rpm 2>&1 | tail -5 || true
            rm -f /tmp/dc-calamares-custom.rpm
        else
            echo "[DC-openSUSE] RPM locale assente — zypper install da repo OBS..."
            zypper --non-interactive --no-gpg-checks install -y calamares kpmcore 2>&1 | tail -15 || true
        fi
    elif [ -z "$_CAL_INST_MAJ" ]; then
        # Calamares assente (nessun rsync o rimosso) — installa da zero
        echo "[DC-openSUSE] Calamares assente — installazione da repo OBS..."
        if [ -f /tmp/dc-calamares-custom.rpm ]; then
            rpm -Uvh --nodeps /tmp/dc-calamares-custom.rpm 2>&1 | tail -5 || true
            rm -f /tmp/dc-calamares-custom.rpm
        else
            zypper --non-interactive --no-gpg-checks install -y calamares kpmcore 2>&1 | tail -15 || true
        fi
    else
        # Versione 3.4+ già presente (copiata da rsync HOST→DEST) — nessuna azione
        echo "[DC-openSUSE] ✓ Calamares $(rpm -q calamares) già aggiornato — nessuna reinstallazione"
        rm -f /tmp/dc-calamares-custom.rpm
    fi
    zypper --non-interactive install -y yad 2>/dev/null || true
    zypper --non-interactive install -y \
        libxcb-util1 xcb-util-cursor libQt6Widgets6 libQt6Quick6 \
        2>&1 | tail -5 || true

    # ── Verifica partition.so ─────────────────────────────────────────────────
    _DC_PART_SO=$(find /usr/lib64/calamares /usr/lib/calamares \
        -name "partition.so" 2>/dev/null | head -1)
    if [ -n "$_DC_PART_SO" ]; then
        echo "[DC-openSUSE] ✓ partition.so: $_DC_PART_SO"
        ldd "$_DC_PART_SO" 2>/dev/null | grep -E "kpmcore|not found" || true
    else
        echo "[DC-openSUSE] WARN: partition.so non trovato nel target"
    fi
fi

if command -v calamares >/dev/null 2>&1; then
    echo "[DC-Fedora] ✓ calamares installato"
    _MISSING=$(ldd $(command -v calamares) 2>/dev/null | grep "not found" | wc -l)
    echo "[DC-Fedora] Librerie mancanti: ${_MISSING}"
else
    echo "[DC-Fedora] ✗ calamares non installato"
fi

# ── Configura calamares per Fedora (branding + sequenza) ─────────────────────
# CRITICO: senza questa configurazione calamares usa branding "auto" di Fedora
# e fallisce con "ERROR: FATAL: none of the expected branding descriptor file paths"
if [ -f /tmp/calamares-config.sh ]; then
    echo "[DC-Fedora] Eseguo calamares-config.sh..."
    if [ -f /tmp/dc_calamares_args ]; then
        _CAL_FAM=$(sed -n "1p" /tmp/dc_calamares_args)
        _CAL_DIST=$(sed -n "2p" /tmp/dc_calamares_args)
        _CAL_BRAND=$(sed -n "3p" /tmp/dc_calamares_args)
    else
        _CAL_FAM="fedora"
        _CAL_DIST="fedora"
        _CAL_BRAND="fedora"
    fi
    bash /tmp/calamares-config.sh "$_CAL_FAM" "$_CAL_DIST" "$_CAL_BRAND" &&         echo "[DC-Fedora] ✓ calamares configurato (famiglia=$_CAL_FAM, branding=$_CAL_BRAND)" ||         echo "[DC-Fedora] ✗ calamares-config.sh fallito"
    rm -f /tmp/calamares-config.sh /tmp/dc_calamares_args 2>/dev/null || true
else
    echo "[DC-Fedora] WARN: calamares-config.sh non trovato in /tmp/"
fi

# ── Locale live → en_US.UTF-8 (Calamares UI parte in inglese) ────────────────
# Installa pacchetto lingua inglese se non presente (Fedora usa glibc-langpack-*)
if command -v dnf >/dev/null 2>&1; then
    dnf install -y glibc-langpack-en 2>&1 | tail -3 || true
fi
# Imposta LANG sistema live (sovrascrive eventuale locale host clonato)
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "LANGUAGE=en_US:en" >> /etc/locale.conf
echo "[DC-Fedora] ✓ locale live impostato: en_US.UTF-8"

# ── Installa altri pacchetti live ────────────────────────────────────────────
echo "[DC-Fedora] Installazione pacchetti live (famiglia: ${DC_FAMILY:-fedora})..."
if command -v dnf >/dev/null 2>&1; then
    dnf install -y   dracut dracut-live   grub2-tools grub2-tools-extra grub2-tools-efi   grub2-efi-x64 efibootmgr mtools squashfs-tools   rsync cryptsetup ImageMagick syslinux xorriso util-linux   xcb-util-cursor libxcb xcb-util   2>&1 | tail -5 || true
elif command -v zypper >/dev/null 2>&1; then
    # openSUSE: pacchetti equivalenti (dracut-live = dracut su openSUSE, syslinux non necessario)
    zypper --non-interactive install -y \
        dracut grub2-x86_64-efi grub2 \
        efibootmgr mtools squashfs \
        rsync cryptsetup ImageMagick xorriso util-linux \
        2>&1 | tail -5 || true
fi

# ── Launcher + icona Install System (distroClone) ────────────────────────────
# Rimuovi default calamares.desktop (usa icona sbagliata dal RPM Fedora)
rm -f /usr/share/applications/calamares.desktop 2>/dev/null || true

# Crea wrapper calamares-launcher (preserva DISPLAY/XAUTHORITY per GDM/sudo)
cat > /usr/local/bin/calamares-launcher << 'CALWRAP'
#!/bin/bash
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
if [ ! -f "$XAUTHORITY" ]; then
    _DISP_USER=$(who | awk 'NR==1{print $1}')
    _AUTH=$(find /home/${_DISP_USER}/.Xauthority /run/user/*/gdm/Xauthority \
        /tmp/.gdm-xauth* 2>/dev/null | head -1)
    [ -f "$_AUTH" ] && export XAUTHORITY="$_AUTH"
fi
if command -v sudo >/dev/null 2>&1; then
    exec sudo -E calamares "$@"
else
    exec pkexec env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" calamares "$@"
fi
CALWRAP
chmod 755 /usr/local/bin/calamares-launcher
echo "[DC-Fedora] ✓ calamares-launcher creato"

# Crea voce menu Install System con icona distroClone
# Cerca icona: pre-chroot copy → branding → hicolor → genera con ImageMagick
_DC_ICON="calamares"
for _ico in \
    "/usr/share/icons/install-system.png" \
    "/usr/share/calamares/branding/distroClone/distroClone-installer.png" \
    "/usr/share/calamares/branding/distroClone/distroClone-logo.png" \
    "/usr/share/calamares/branding/distroClone/logo.png" \
    "/usr/share/icons/hicolor/256x256/apps/distroClone.png" \
    "/usr/share/pixmaps/distroClone.png"; do
    [ -f "$_ico" ] && _DC_ICON="$_ico" && break
done
# Fallback: genera icona esagonale DC con ImageMagick se disponibile
if [ "$_DC_ICON" = "calamares" ]; then
    for _im in convert magick; do
        if command -v "$_im" >/dev/null 2>&1; then
            mkdir -p /usr/share/pixmaps
            "$_im" -size 256x256 xc:transparent \
                -fill '#0d47a1' \
                -draw 'polygon 128,6 228,58 228,198 128,250 28,198 28,58' \
                -fill '#2196f3' \
                -draw 'polygon 128,58 184,88 184,168 128,198 72,168 72,88' \
                -fill 'white' -pointsize 56 -gravity center \
                -annotate +0+0 'DC' \
                /usr/share/pixmaps/distroClone.png 2>/dev/null && \
                _DC_ICON="/usr/share/pixmaps/distroClone.png" && break || true
        fi
    done
fi
echo "[DC-Fedora] Icona selezionata: $_DC_ICON"
cat > /usr/share/applications/install-system.desktop << DESKTOPEOF
[Desktop Entry]
Type=Application
Name=Install System
Comment=Install this system to disk
Exec=/usr/local/bin/calamares-launcher
Icon=${_DC_ICON}
Terminal=false
Categories=System;Installer;
StartupNotify=true
DESKTOPEOF
chmod 644 /usr/share/applications/install-system.desktop
echo "[DC-Fedora] ✓ install-system.desktop creato (icon: ${_DC_ICON})"

# Copia icona sul Desktop di liveuser
_LU="${DC_LIVE_USER:-liveuser}"
mkdir -p "/home/${_LU}/Desktop"
install -Dm644 /usr/share/applications/install-system.desktop \
    "/home/${_LU}/Desktop/install-system.desktop"
chmod 755 "/home/${_LU}/Desktop/install-system.desktop"
chown "${_LU}:${_LU}" "/home/${_LU}/Desktop/install-system.desktop"
echo "[DC-Fedora] ✓ icona Install System su Desktop di ${_LU}"

# GNOME: meccanismo trust per esecuzione senza dialog "Allow Launching"
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/dc-trust-launchers.desktop << 'TRSTDT'
[Desktop Entry]
Type=Application
Name=Trust Desktop Launchers
Exec=/bin/bash -c 'sleep 3; for f in "$HOME/Desktop/install-system.desktop"; do [ -f "$f" ] && chmod +x "$f" && gio set "$f" metadata::trusted true 2>/dev/null; done'
OnlyShowIn=GNOME;
X-GNOME-Autostart-enabled=true
NoDisplay=true
TRSTDT
echo "[DC-Fedora] ✓ trust launcher impostato per GNOME"
update-desktop-database /usr/share/applications 2>/dev/null || true

# Configura dracut per live system (solo in /run — NON in /etc/dracut.conf.d)
# IMPORTANTE: il file in /etc/dracut.conf.d finisce nel squashfs e nel target
# installato, dove Calamares rigenera initramfs → dracut fallisce con dmsquash-live
# Usiamo /run/dracut che è tmpfs e NON viene incluso nel squashfs
mkdir -p /run/dracut
cat > /run/dracut/99-distroClone-live.conf << 'DRACUT_EOF'
# DistroClone live boot — solo per boot live, NON copiato nel target
add_dracutmodules+=" dmsquash-live "
add_drivers+=" squashfs loop "
compress="xz"
DRACUT_EOF
# Symlink temporaneo per il boot live (verrà rimosso dopo il boot)
mkdir -p /etc/dracut.conf.d
ln -sf /run/dracut/99-distroClone-live.conf     /etc/dracut.conf.d/99-distroClone-live.conf 2>/dev/null ||     cp /run/dracut/99-distroClone-live.conf     /etc/dracut.conf.d/99-distroClone-live.conf
echo "[DC-Fedora] → dracut live configurato (temporaneo, non incluso nel target)"

# Rigenera initramfs con moduli live (non fatale — Calamares lo farà al momento dell'installazione)
KERNEL_VER=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | tail -1)
if [ -n "$KERNEL_VER" ]; then
    if dracut --force --add "dmsquash-live" \
           "/boot/initramfs-${KERNEL_VER}.img" \
           "$KERNEL_VER" 2>/dev/null; then
        echo "[DC-Fedora] ✓ initramfs rigenerato per kernel $KERNEL_VER"
    else
        # Fallback: rigenera senza moduli aggiuntivi
        dracut --force "/boot/initramfs-${KERNEL_VER}.img" "$KERNEL_VER" 2>/dev/null || \
            echo "[DC-Fedora] initramfs non rigenerato (sarà fatto da Calamares)"
    fi
else
    dracut --force /boot/initramfs-live.img 2>/dev/null || \
        echo "[DC-Fedora] initramfs non rigenerato (kernel non trovato)"
fi

# ── Abilita udisks2 e polkit (necessari per kpmcore / modulo partition) ──────
# Calamares partition module usa kpmcore che si connette a udisks2 via D-Bus.
# Senza udisks2 attivo, kpmcore va in timeout D-Bus alla schermata Welcome.
for _SVC in udisks2 polkit; do
    if systemctl list-unit-files "${_SVC}.service" 2>/dev/null | grep -q "${_SVC}"; then
        systemctl enable "${_SVC}.service" 2>/dev/null && \
            echo "[DC-Fedora] ✓ ${_SVC}.service abilitato" || \
            echo "[DC-Fedora] WARN: ${_SVC}.service non abilitabile"
    fi
done

CHROOT_FEDORA_EOF
    ;; # fine case fedora|opensuse

  # ════════════════════════════════════════════════════════════════════════════

  *)
    echo "[DC] WARN: famiglia '$DC_FAMILY' non supportata per chroot config"
    echo "[DC] La ISO potrebbe non avviare correttamente"
    ;;

esac # fine branch famiglia distro
# ─────────────────────────────────────────────────────────────────────────────

log_msg "  $MSG_CHROOT_DONE"

# Sostituisci branding statico con quello dinamico (tutti i settings.conf, Debian + Arch)
echo "  → Dynamic branding configuration in settings.conf"
_BRAND_UPDATED=0
for _sf in \
    "$DEST/etc/calamares/settings.conf" \
    "$DEST/usr/share/calamares/settings.conf" \
    "$DEST/usr/share/calamares/settings_online.conf" \
    "$DEST/usr/share/calamares/settings_offline.conf"; do
    if [ -f "$_sf" ]; then
        sed -i "s/^branding: .*$/branding: distroClone/" "$_sf"
        echo "  ✓ branding aggiornato: $_sf"
        _BRAND_UPDATED=1
    fi
done
[ "$_BRAND_UPDATED" -eq 0 ] && echo "  ⚠ settings.conf non trovato — verrà configurato da calamares-config.sh nel chroot"

############################################
# [17/30] HOOK POST-INSTALL
############################################
log_msg "$MSG_STEP17"

# Assicura che le directory systemd esistano (fix 46: su alcuni Fedora rootfs mancano)
mkdir -p "$DEST/etc/systemd/system/multi-user.target.wants"

# Scrive la unit NEL filesystem che finirà installato (DEST)
tee "$DEST/etc/systemd/system/remove-live-admin.service" > /dev/null << 'EOF'

[Unit]
Description=Cleanup live system after installation
After=local-fs.target systemd-user-sessions.service
# Fix 49a: rimosso Before=display-manager.service — bloccava GDM per 2-3 min
# (dnf remove calamares + dnf autoremove girano DOPO che il desktop è già visibile)
# Non eseguire in ambiente live (Debian: boot=live, Fedora: rd.live.image, Arch: archiso)
ConditionKernelCommandLine=!boot=live
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/run/live
ConditionPathExists=!/run/initramfs/live
ConditionPathExists=!/run/rootfsbase
# Arch/archiso: /run/archiso/bootmnt esiste solo nel live, non sul sistema installato
ConditionPathExists=!/run/archiso/bootmnt
ConditionPathExists=!/run/archiso

[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
TimeoutStartSec=600
# Verifica doppia che non siamo in un live environment
ExecStart=/bin/bash -c '{ grep -qE "boot=live|rd\.live\.image|live-media|archisobasedir" /proc/cmdline || [ -e /run/archiso/bootmnt ] || [ -e /run/archiso ]; } && { echo "Live environment detected, skipping cleanup"; exit 0; } || true'
RemainAfterExit=no

# ── LOG: snapshot /home PRIMA di qualsiasi cleanup ─────────────────────────
# Serve per diagnosticare cosa cancella /home al primo boot
ExecStartPost=-/bin/bash -c 'mkdir -p /var/log; { echo "=== remove-live-admin START $(date) ==="; echo "--- /home ---"; ls -la /home/ 2>/dev/null || echo "MANCANTE"; echo "--- passwd UID>=1000 ---"; awk -F: '"'"'$3>=1000 && $3<65534{print}'"'"' /etc/passwd; echo "--- distroClone-live-user ---"; cat /etc/distroClone-live-user 2>/dev/null || echo "non trovato"; echo "--- /proc/cmdline ---"; cat /proc/cmdline; } > /var/log/dc-firstboot.log 2>&1'

# ── Disabilita servizi live Arch/CachyOS che potrebbero girare al primo boot ──
# Questi servizi sono nel squashfs e vengono copiati nel sistema installato.
# Se non disabilitati, eseguono cleanup aggressivo (userdel, rm /home, ecc.)
ExecStartPost=-/bin/bash -c 'for svc in cachyos-live.service cachyos-firstboot.service cachyos-configure-after-reboot.service garuda-firstrun.service garuda-setup-assistant.service garuda-live.service archiso-reconfiguration.service archiso-keyring-populate.service archiso-copy-passwd.service archiso.service pacman-init.service clean-live.service livesys.service livesys-late.service; do systemctl disable "$svc" 2>/dev/null && echo "disabled: $svc" >> /var/log/dc-firstboot.log || true; done'

# Wait for dpkg lock
ExecStartPost=-/bin/bash -c 'for i in $(seq 1 60); do fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break; sleep 5; done'

# Fedora: proteggi pacchetti di sistema da autoremove PRIMA della rimozione
# openssl e python3 potrebbero essere rimossi come dipendenze orfane di calamares/dracut-live
ExecStartPost=-/bin/bash -c 'command -v dnf >/dev/null 2>&1 && dnf mark install openssl python3 bash coreutils shadow-utils 2>/dev/null || true'

# Remove live packages + Calamares + build tools (cross-distro)
# CRITICO per Arch/CachyOS: --noscriptlet impedisce l'esecuzione di post_remove()
# del .install file di calamares (CachyOS) che rimuove aggressivamente /home e utenti live.
# Senza --noscriptlet: pacman esegue post_remove() → userdel -r archie / rm -rf /home/* → /home sparisce.
ExecStartPost=-/bin/bash -c 'if command -v apt-get >/dev/null 2>&1; then apt-get -y purge live-boot live-boot-doc live-config live-config-systemd live-tools calamares calamares-settings-debian isolinux syslinux-common syslinux-utils mtools squashfs-tools 2>/dev/null || true; elif command -v dnf >/dev/null 2>&1; then dnf remove -y calamares dracut-live 2>/dev/null || true; elif command -v pacman >/dev/null 2>&1; then pacman -R --noconfirm --noscriptlet calamares 2>/dev/null || true; pacman -R --noconfirm --noscriptlet cachyos-live-services cachyos-calamares-config garuda-live garuda-setup-assistant 2>/dev/null || true; fi'

# Cleanup cache (cross-distro)
ExecStartPost=-/bin/bash -c 'if command -v apt-get >/dev/null 2>&1; then apt-get -y autoremove --purge && apt-get clean; elif command -v dnf >/dev/null 2>&1; then dnf autoremove -y && dnf clean all; elif command -v pacman >/dev/null 2>&1; then pacman -Scc --noconfirm; fi'
ExecStartPost=-/bin/bash -c 'sleep 10; if command -v apt-get >/dev/null 2>&1; then apt-get -y purge calamares calamares-settings-debian 2>/dev/null || true; fi' 

# Remove Calamares leftovers/icons
ExecStartPost=-/usr/bin/find /usr/share/applications -maxdepth 1 -type f -iname '*calamares*.desktop' -delete
ExecStartPost=-/usr/bin/find /usr/share/applications -maxdepth 1 -type f \( -iname 'liveinst*.desktop' -o -iname 'anaconda*.desktop' \) -delete
ExecStartPost=-/bin/rm -f /etc/xdg/autostart/liveinst-setup.desktop
ExecStartPost=-/usr/bin/update-desktop-database

# Remove Debian Installer desktop entry (Install Debian)
ExecStartPost=-/usr/bin/find /usr/share/applications -maxdepth 1 -type f \( -iname 'debian-installer*.desktop' -o -iname '*debian*install*.desktop' \) -delete
ExecStartPost=-/usr/bin/find /etc/xdg/autostart -maxdepth 1 -type f \( -iname 'debian-installer*.desktop' -o -iname '*debian*install*.desktop' \) -delete
ExecStartPost=-/usr/bin/update-desktop-database

# Remove installer launchers/icons after installation
ExecStartPost=-/bin/rm -f /usr/share/applications/calamares-install-debian.desktop
ExecStartPost=-/bin/rm -f /usr/share/applications/install-system.desktop
ExecStartPost=-/bin/bash -c 'rm -f /home/*/Desktop/calamares-install-debian.desktop /home/*/Desktop/install-system.desktop 2>/dev/null || true'
ExecStartPost=-/bin/rm -f /etc/skel/Desktop/calamares-install-debian.desktop
ExecStartPost=-/bin/rm -f /etc/skel/Desktop/install-system.desktop
ExecStartPost=-/usr/bin/update-desktop-database

# Remove DistroClone menu entry (binaries not present on target)
ExecStartPost=-/bin/rm -f /usr/share/applications/distroClone.desktop

# Remove Imagemagick menu entry (binaries not present DistroClone)
ExecStartPost=-/bin/bash -c 'if command -v apt-get >/dev/null 2>&1; then apt-get -y purge imagemagick-7-common; apt-get -y autoremove --purge; apt-get clean; elif command -v dnf >/dev/null 2>&1; then dnf remove -y ImageMagick 2>/dev/null || true; fi' 
ExecStartPost=-/bin/rm -f /usr/share/applications/display-im7.q16.desktop
ExecStartPost=-/usr/bin/update-desktop-database

# (Opzionale) se aggiungi il fix GNOME "trusted launcher", pulisci anche quello
ExecStartPost=-/bin/rm -f /etc/xdg/autostart/syslinuxos-trust-desktop-launchers.desktop
ExecStartPost=-/bin/rm -f /usr/local/bin/syslinuxos-trust-desktop-launchers.sh

# Rimuovi autologin del live user — se rimane, LightDM/SDDM/GDM provano a loggare
# un utente che non esiste più e la schermata di login potrebbe apparire rotta
ExecStartPost=-/bin/bash -c 'sed -i "/^autologin-user=/d;/^autologin-user-timeout=/d;/^autologin-session=/d" /etc/lightdm/lightdm.conf 2>/dev/null || true'
ExecStartPost=-/bin/rm -f /etc/lightdm/lightdm.conf.d/50-distroClone-autologin.conf
ExecStartPost=-/bin/rm -f /etc/sddm.conf.d/autologin.conf
ExecStartPost=-/bin/bash -c 'sed -i "/^AutomaticLoginEnable=/d;/^AutomaticLogin=/d;/^TimedLoginEnable=/d" /etc/gdm/custom.conf /etc/gdm3/custom.conf 2>/dev/null || true'

# Delete live user — legge l'utente live da /etc/distroClone-live-user se presente
# NOTA: awk usa \$3 (campo awk), NON $3 (positional bash) — distinzione critica dentro bash -c '...'
# Senza \$3 il $3 verrebbe espanso da bash a "" → awk fallisce → _N_USERS="" → protezione bypassata
# PROTEZIONE: non eliminare l'utente se è l'unico UID>=1000 (= utente reale scelto in Calamares)
ExecStartPost=-/bin/bash -c '_DC_LU=$(cat /etc/distroClone-live-user 2>/dev/null | tr -d "[:space:]"); _N_USERS=$(awk -F: "\$3>=1000 && \$3<65534{n++} END{print n+0}" /etc/passwd); for u in admin liveuser live archie ${_DC_LU}; do [ -z "$u" ] && continue; id "$u" >/dev/null 2>&1 || continue; if [ "$_N_USERS" -le 1 ]; then echo "SKIP: $u unico utente reale" >> /var/log/dc-firstboot.log; continue; fi; _H=$(getent passwd "$u" | cut -d: -f6); userdel "$u" 2>/dev/null || deluser "$u" 2>/dev/null || true; [ -n "$_H" ] && [ "$_H" != "/" ] && rm -rf "$_H" 2>/dev/null; echo "removed: $u (home=$_H)" >> /var/log/dc-firstboot.log; _N_USERS=$((_N_USERS - 1)); done'

# Remove host network configurations (WiFi, Ethernet connections from build system)
ExecStartPost=-/bin/rm -rf /etc/NetworkManager/system-connections/*
ExecStartPost=-/bin/rm -rf /var/lib/NetworkManager/*
ExecStartPost=-/bin/rm -f /etc/netplan/*.yaml
ExecStartPost=-/bin/rm -f /etc/wpa_supplicant/wpa_supplicant.conf
ExecStartPost=-/bin/systemctl restart NetworkManager

# Clean icon cache (non fatal)
ExecStartPost=-/bin/rm -rf /usr/share/icons/hicolor/icon-theme.cache

# Rimuovi pacchetti LUKS solo se root NON è cifrato
# (se cifrato, cryptsetup-initramfs deve rimanere!)
#ExecStartPost=-/bin/bash -c 'if ! grep -q luks /etc/crypttab 2>/dev/null; then apt-get -y purge cryptsetup-bin; fi'
ExecStartPost=-/usr/sbin/update-initramfs -u -k all

# Remove self (non fatal)
ExecStartPost=-/bin/systemctl disable --now remove-live-admin.service
ExecStartPost=-/bin/rm -f /etc/systemd/system/remove-live-admin.service

# Remove self calamares-live-user
ExecStartPost=-/bin/rm -f /usr/local/bin/calamares-remove-live-user.sh

# Remove DistroClone-created scripts (not part of any package)
ExecStartPost=-/bin/rm -f /usr/local/bin/calamares-grub-install.sh
ExecStartPost=-/bin/rm -f /usr/local/bin/dc-post-users.sh
ExecStartPost=-/bin/rm -f /usr/local/bin/dc-remove-live-user.sh
ExecStartPost=-/bin/rm -rf /etc/calamares
ExecStartPost=-/bin/rm -rf /usr/share/calamares
ExecStartPost=-/bin/rm -f /etc/distroClone-live-user

# ── LOG: snapshot /home DOPO il cleanup ────────────────────────────────────
ExecStartPost=-/bin/bash -c '{ echo "=== remove-live-admin END $(date) ==="; echo "--- /home dopo cleanup ---"; ls -la /home/ 2>/dev/null || echo "MANCANTE"; echo "--- passwd UID>=1000 ---"; awk -F: "\$3>=1000 && \$3<65534{print}" /etc/passwd; } >> /var/log/dc-firstboot.log 2>&1'

# ── SAFETY NET: ricostruisce /home e le home degli utenti reali se mancanti ─
# Gira sempre per ultima — protegge da qualsiasi servizio che abbia rimosso /home
ExecStartPost=-/bin/bash -c 'mkdir -p /home; awk -F: "\$3>=1000 && \$3<65534 && \$6~/^\/home\//{print \$1\":\"\$3\":\"\$4\":\"\$6}" /etc/passwd | while IFS=: read u uid gid home; do [ -d "$home" ] && continue; mkdir -p "$home"; cp -a /etc/skel/. "$home/" 2>/dev/null || true; chown -R "${uid}:${gid}" "$home"; chmod 700 "$home"; echo "SAFETY NET: ricreata $home per $u" >> /var/log/dc-firstboot.log; done'

[Install]
WantedBy=multi-user.target
EOF

# Abilita la unit nel chroot installabile.
# systemctl --root opera offline dall'host (crea solo symlink, non connette D-Bus).
# chroot + daemon-reload fallisce senza systemd in esecuzione → set -e abortiva lo script.
systemctl --root="$DEST" enable remove-live-admin.service 2>/dev/null || \
    ln -sf /etc/systemd/system/remove-live-admin.service \
       "$DEST/etc/systemd/system/multi-user.target.wants/remove-live-admin.service" || true

############################################
# PATCH PASSWORD — DIRETTAMENTE SU $DEST/etc/shadow
# Fatto dall'HOST dopo il chroot: bypassa tutti i limiti chroot
# (openssl, usermod, chpasswd non disponibili/affidabili dentro chroot)
# SKIP per Arch: il chroot Arch imposta già correttamente le password
# via chpasswd; questa patch userebbe ROOT_PASSWORD (≠ _LIVE_PWD)
# e potrebbe corrompere shadow se _PATCH_USER non coincide.
############################################
if [ "${DC_FAMILY:-}" = "arch" ]; then
    echo "[DC] Arch: PATCH PASSWORD saltata — password già impostata nel chroot"
else
# Leggi il nome utente reale rilevato dal chroot Arch
# (il chroot scrive il nome in /tmp/dc_actual_live_user = $DEST/tmp/dc_actual_live_user)
# Fix 46c: || true necessario — con set -e + set -o pipefail, se il file non esiste
# (Fedora: non scritto dal chroot Fedora, solo da quello Arch), cat esce con 1,
# la pipeline esce con 1, l'assegnazione esce con 1 → set -e abortisce lo script.
_ACTUAL_LIVE=$(cat "$DEST/tmp/dc_actual_live_user" 2>/dev/null | tr -d '[:space:]') || true
if [ -n "$_ACTUAL_LIVE" ] && [ "$_ACTUAL_LIVE" != "$_DC_LIVE_USER" ]; then
    echo "[DC] Utente live rilevato dal chroot: $_ACTUAL_LIVE (era: ${_DC_LIVE_USER:-non impostato})"
    _DC_LIVE_USER="$_ACTUAL_LIVE"
fi
_PATCH_USER="${_DC_LIVE_USER:-admin}"
_PATCH_PWD="${ROOT_PASSWORD:-root}"

echo "[DC] Impostazione password per ${_PATCH_USER} direttamente su $DEST/etc/shadow..."

# Genera hash SHA-512 dall'HOST — cascata di metodi, set -e safe (|| true)
_PATCH_HASH=""
# Metodo 1: openssl (disponibile su quasi tutte le distro)
_PATCH_HASH=$(openssl passwd -6 "${_PATCH_PWD}" 2>/dev/null) || true
if [ -z "$_PATCH_HASH" ]; then
    # Metodo 2: mkpasswd (whois/expect su Debian, expect su Fedora)
    _PATCH_HASH=$(mkpasswd -m sha-512 "${_PATCH_PWD}" 2>/dev/null) || true
fi
if [ -z "$_PATCH_HASH" ]; then
    # Metodo 3: python3 con passlib (Python 3.13+, crypt rimosso da Python 3.13)
    _PATCH_HASH=$(python3 -c "from passlib.hash import sha512_crypt; import sys; print(sha512_crypt.hash(sys.argv[1]))" \
        "${_PATCH_PWD}" 2>/dev/null) || true
fi
if [ -z "$_PATCH_HASH" ]; then
    # Metodo 4: python3 legacy crypt (Python < 3.13)
    _PATCH_HASH=$(python3 -c "import crypt,sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA512)))" \
        "${_PATCH_PWD}" 2>/dev/null) || true
fi

if [ -n "$_PATCH_HASH" ] && [ -f "$DEST/etc/shadow" ]; then
    # ── 1. Assicura che _PATCH_USER esista in /etc/passwd ────────────────────
    if ! grep -q "^${_PATCH_USER}:" "$DEST/etc/passwd"; then
        echo "[DC] WARN: ${_PATCH_USER} non in passwd — aggiungo entry di emergenza..."
        # Cerca UID 1000 disponibile (se già preso, usa il successivo libero)
        _P_UID=1000
        while grep -q ":${_P_UID}:" "$DEST/etc/passwd" 2>/dev/null; do
            _P_UID=$(( _P_UID + 1 ))
        done
        echo "${_PATCH_USER}:x:${_P_UID}:${_P_UID}:Live User:/home/${_PATCH_USER}:/bin/bash" \
            >> "$DEST/etc/passwd"
        # Aggiungi gruppo primario se mancante
        if ! grep -q "^${_PATCH_USER}:" "$DEST/etc/group"; then
            echo "${_PATCH_USER}:x:${_P_UID}:" >> "$DEST/etc/group"
        fi
        # Aggiungi a wheel/sudo
        sed -i "s/^wheel:\(.*\)/wheel:\1,${_PATCH_USER}/" "$DEST/etc/group" 2>/dev/null || true
        sed -i "s/^sudo:\(.*\)/sudo:\1,${_PATCH_USER}/"  "$DEST/etc/group" 2>/dev/null || true
        # Aggiungi gruppo autologin (richiesto da LightDM su Arch)
        if ! grep -q "^autologin:" "$DEST/etc/group"; then
            echo "autologin:x:969:${_PATCH_USER}" >> "$DEST/etc/group"
        else
            sed -i "s/^autologin:\(.*\)/autologin:\1,${_PATCH_USER}/" "$DEST/etc/group" 2>/dev/null || true
        fi
        # Crea home directory se mancante
        mkdir -p "$DEST/home/${_PATCH_USER}"
        chmod 755 "$DEST/home/${_PATCH_USER}"
        echo "[DC] ✓ ${_PATCH_USER} aggiunto a passwd/group (UID ${_P_UID}), home creata"
    else
        echo "[DC] ✓ ${_PATCH_USER} già presente in passwd"
    fi

    # ── 2. Aggiorna shadow ───────────────────────────────────────────────────
    if grep -q "^${_PATCH_USER}:" "$DEST/etc/shadow"; then
        sed -i "s|^${_PATCH_USER}:[^:]*:|${_PATCH_USER}:${_PATCH_HASH}:|" "$DEST/etc/shadow"
        echo "[DC] ✓ Password aggiornata per ${_PATCH_USER} in shadow"
    else
        echo "${_PATCH_USER}:${_PATCH_HASH}:19000:0:99999:7:::" >> "$DEST/etc/shadow"
        echo "[DC] ✓ Riga shadow aggiunta per ${_PATCH_USER}"
    fi
    # Aggiorna anche root
    if grep -q "^root:" "$DEST/etc/shadow"; then
        sed -i "s|^root:[^:]*:|root:${_PATCH_HASH}:|" "$DEST/etc/shadow"
        echo "[DC] ✓ Password aggiornata per root in shadow"
    fi
    # Verifica finale
    echo "[DC] Verifica passwd+shadow:"
    grep -E "^(root|${_PATCH_USER}):" "$DEST/etc/passwd" || true
    grep -E "^(root|${_PATCH_USER}):" "$DEST/etc/shadow" | sed 's/:\$[^:]*:/:[HASH_OK]:/g' || true
else
    echo "[DC] WARN: impossibile generare hash password (openssl e python3 non disponibili?)"
fi
fi  # fine else "not arch"

# Disabilita livesys.service e altri servizi Fedora che resettano password al boot
for _lsvc in livesys livesys-late initial-setup; do
    [ -f "$DEST/usr/lib/systemd/system/${_lsvc}.service" ] &&         ln -sf /dev/null "$DEST/etc/systemd/system/${_lsvc}.service" &&         echo "[DC] ✓ ${_lsvc}.service disabilitato (resettava password live)" || true
done
# Rimuovi script livesys che imposta password vuota
[ -f "$DEST/usr/sbin/livesys" ] &&     sed -i 's/passwd -d liveuser/# passwd -d liveuser  # disabled by DistroClone/'     "$DEST/usr/sbin/livesys" 2>/dev/null || true

############################################
# [18/30] UMOUNT CHROOT
############################################
log_msg "$MSG_STEP18"

# Usa cleanup_chroot_mounts() (umount -R ricorsivo) definita nel blocco sanitation
cleanup_chroot_mounts
# Smonta anche tmp se montato (non gestito da cleanup_chroot_mounts)
mountpoint -q "$DEST/tmp" && umount -l "$DEST/tmp" 2>/dev/null || true

############################################
# [19/30] SANITY CHECK
############################################
log_msg "$MSG_STEP19"

for d in boot boot/efi; do
  [ -d "$DEST/$d" ] || { echo "$MSG_ERR_MISSING $DEST/$d"; exit 1; }
done
# boot/grub o boot/grub2 (Fedora usa grub2/)
if [ ! -d "$DEST/boot/grub" ] && [ ! -d "$DEST/boot/grub2" ]; then
  echo "$MSG_ERR_MISSING $DEST/boot/grub[2]"; exit 1
fi

############################################
# [19b/30] STATIC TESTS — target filesystem
############################################
_DC_STATIC_WARN=0
_dc_swarn() { echo "[TEST WARN] $*"; _DC_STATIC_WARN=$((_DC_STATIC_WARN+1)); }

# T1: kernel presente nel target
if ! compgen -G "$DEST/boot/vmlinuz*" >/dev/null 2>&1; then
    _dc_swarn "nessun vmlinuz* in $DEST/boot/ — kernel non trovato"
fi

if [ "${DC_FAMILY:-arch}" = "arch" ]; then
    # T2: mkinitcpio.conf presente
    if [ ! -f "$DEST/etc/mkinitcpio.conf" ]; then
        _dc_swarn "mkinitcpio.conf assente in $DEST/etc/ — mkinitcpio non potrà girare"
    fi
    # T3: almeno un preset
    if ! compgen -G "$DEST/etc/mkinitcpio.d/*.preset" >/dev/null 2>&1; then
        _dc_swarn "nessun preset in $DEST/etc/mkinitcpio.d/ — dc-ensure-presets dovrà crearli"
    fi
    # T4: initramfs presente (serve per il boot della live ISO)
    if ! compgen -G "$DEST/boot/initramfs-*.img" >/dev/null 2>&1; then
        _dc_swarn "nessun initramfs-*.img in $DEST/boot/ — boot live non funzionerà"
    fi
fi

if [ "$_DC_STATIC_WARN" -gt 0 ]; then
    echo "[DC][19b] Static test: $_DC_STATIC_WARN warning(s) — vedi sopra"
else
    echo "[DC][19b] Static test target: OK"
fi

############################################
# [20/30] KERNEL + INITRD
############################################
log_msg "$MSG_STEP20"

# ── Kernel/initrd detection by distro family ────────────────────────────────
# Debian:  vmlinuz-<ver>       + initrd.img-<ver>
# Arch:    vmlinuz-linux       + initramfs-linux.img
# Fedora:  vmlinuz-<ver>       + initramfs-<ver>.img (generated by dracut)
# openSUSE: vmlinuz-<ver>      + initrd-<ver>
# ─────────────────────────────────────────────────────────────────────────────

KERNEL=""
INITRD=""

# DEBUG: show /boot contents before searching for kernel/initrd
echo "[DC] DEBUG boot dir ($DC_FAMILY): $(ls "$DEST"/boot/ 2>/dev/null | tr '\n' ' ')"

# set -e disabled for the entire kernel/initrd search:
# ls on unmatched glob returns exit 2 and would cause silent exit
set +e
case "${DC_FAMILY:-arch}" in
  arch)
    # Kernel glob catches linux, linux-zen, linux-cachyos, etc.
    KERNEL=$(ls "$DEST"/boot/vmlinuz-linux* 2>/dev/null | sort -V | tail -n1)
    # Fix 34: prefer initramfs-live.img (generated by _dc_build_mkinitcpio
    # without PXE drop-in) over the standard preset path
    if [ -f "$DEST/boot/initramfs-live.img" ]; then
        INITRD="$DEST/boot/initramfs-live.img"
        echo "[DC] Arch: using dedicated initramfs-live.img"
    else
        INITRD=$(ls "$DEST"/boot/initramfs-linux*.img 2>/dev/null | grep -v fallback | sort -V | tail -n1)
        [ -z "$INITRD" ] && INITRD=$(ls "$DEST"/boot/initramfs-*.img 2>/dev/null | grep -v fallback | sort -V | tail -n1)
    fi
    # Boot params based on detected live stack (archiso vs dracut-live)
    case "${DC_LIVE_STACK:-archiso}" in
      archiso)
        # archiso hook: /${archisobasedir}/${arch}/airootfs.sfs
        DC_BOOT_PARAMS="archisobasedir=arch archisolabel=${ISO_LABEL} quiet"
        ;;
      dracut-live)
        # Garuda/dracut: dmsquash-live module
        DC_BOOT_PARAMS="rd.live.image root=live:CDLABEL=${ISO_LABEL} rd.live.overlay.overlayfs=1 quiet"
        ;;
    esac
    ;;
  fedora|opensuse)
    # On Fedora /boot is often a separate partition not included in rsync.
    # Look first in $DEST/boot/, then in HOST /boot/ (physical partition).
    _FEDORA_BOOT_DIRS=("$DEST/boot" "/boot")
    for _bdir in "${_FEDORA_BOOT_DIRS[@]}"; do
        [ -z "$KERNEL" ] && KERNEL=$(ls "$_bdir"/vmlinuz-* 2>/dev/null | sort -V | tail -n1)
        [ -z "$KERNEL" ] && KERNEL=$(ls "$_bdir"/vmlinuz 2>/dev/null | head -n1)
    done
    for _bdir in "${_FEDORA_BOOT_DIRS[@]}"; do
        [ -z "$INITRD" ] && INITRD=$(ls "$_bdir"/initramfs-*.img 2>/dev/null | grep -v rescue | sort -V | tail -n1)
    done
    echo "[DC] DEBUG — boot dirs: ${_FEDORA_BOOT_DIRS[*]}"
    echo "[DC] DEBUG — kernel:    $KERNEL"
    echo "[DC] DEBUG — initrd:    $INITRD"
    # If kernel/initrd come from host /boot/, copy them into $DEST/boot/
    if [ -n "$KERNEL" ] && [[ "$KERNEL" != "$DEST"* ]]; then
        echo "[DC] Fedora: separate /boot — copying kernel/initrd into rootfs..."
        mkdir -p "$DEST/boot"
        cp -f "$KERNEL" "$DEST/boot/"
        KERNEL="$DEST/boot/$(basename "$KERNEL")"
        if [ -n "$INITRD" ] && [ -f "$INITRD" ]; then
            cp -f "$INITRD" "$DEST/boot/"
            INITRD="$DEST/boot/$(basename "$INITRD")"
        fi
    fi
    # Last resort: regenerate initramfs
    if [ -z "$INITRD" ] || [ ! -f "$INITRD" ]; then
        if [ -n "$KERNEL" ]; then
            _KVER=$(basename "$KERNEL" | sed 's/vmlinuz-//')
            echo "[DC] Regenerating initramfs for kernel $_KVER..."
            chroot "$DEST" dracut --force                 "/boot/initramfs-${_KVER}.img" "$_KVER" 2>/dev/null || true
            INITRD="$DEST/boot/initramfs-${_KVER}.img"
        fi
    fi
    DC_BOOT_PARAMS="rd.live.image root=live:CDLABEL=${ISO_LABEL} rd.live.overlay.overlayfs quiet"
    ;;
  *)
    KERNEL=$(ls "$DEST"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1)
    INITRD=$(ls "$DEST"/boot/initrd* 2>/dev/null | sort -V | tail -n1)
    DC_BOOT_PARAMS="boot=live quiet splash"
    ;;
esac

# ── Universal fallback: separate /boot partition (Fedora, openSUSE, etc.) ────
echo "[DC] DEBUG /boot host: $(ls /boot/ 2>/dev/null | tr '
' ' ')"
echo "[DC] DEBUG KERNEL dopo case: '$KERNEL'"
echo "[DC] DEBUG INITRD dopo case: '$INITRD'"

if [ -z "$KERNEL" ] || [ ! -f "$KERNEL" ]; then
    echo "[DC] $DEST/boot/ empty — looking in host /boot/..."
    # Fedora BLS: vmlinuz-<ver> in /boot/
    KERNEL="$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1)"
    # Fallback: vmlinuz without version suffix
    [ -z "$KERNEL" ] && KERNEL="$(ls /boot/vmlinuz 2>/dev/null | head -n1)"
    # Fallback EFI BLS: /boot/efi/EFI/fedora/vmlinuz (rare)
    [ -z "$KERNEL" ] && KERNEL="$(find /boot/efi /boot/loader/entries -name 'vmlinuz*' 2>/dev/null | sort -V | tail -n1)"
    if [ -n "$KERNEL" ] && [ -f "$KERNEL" ]; then
        echo "[DC] ✓ Kernel host: $KERNEL"
        mkdir -p "$DEST/boot"
        cp -f "$KERNEL" "$DEST/boot/"
        KERNEL="$DEST/boot/$(basename "$KERNEL")"
    else
        echo "[DC] WARN — kernel not found even in host /boot/"
    fi
fi

if [ -z "$INITRD" ] || [ ! -f "$INITRD" ]; then
    INITRD="$(ls /boot/initramfs-*.img 2>/dev/null | grep -v rescue | sort -V | tail -n1)"
    [ -z "$INITRD" ] && INITRD="$(ls /boot/initrd.img-* /boot/initrd-* 2>/dev/null | grep -v rescue | sort -V | tail -n1)"
    if [ -n "$INITRD" ] && [ -f "$INITRD" ]; then
        echo "[DC] ✓ Initrd host: $INITRD"
        mkdir -p "$DEST/boot"
        cp -f "$INITRD" "$DEST/boot/"
        INITRD="$DEST/boot/$(basename "$INITRD")"
    else
        echo "[DC] WARN — initrd not found even in host /boot/"
    fi
fi

# ── Regenerate LIVE initramfs (Fedora/openSUSE only, with separate /boot) ────
# On Fedora the kernel may come from host /boot → initramfs lacks dmsquash-live.
# On Arch/dracut-live (Garuda) this block is NOT executed:
#   host dracut regeneration happens later in its dedicated block.
if [ "${DC_FAMILY:-arch}" = "fedora" ] || [ "${DC_FAMILY:-arch}" = "opensuse" ]; then
  if [ -n "$KERNEL" ] && [ -f "$KERNEL" ]; then
    _KVER_LIVE=$(basename "$KERNEL" | sed 's/vmlinuz-//')
    _INITRD_LIVE="$DEST/boot/initramfs-${_KVER_LIVE}-live.img"
    echo "[DC] Regenerating live initramfs for $_KVER_LIVE (dmsquash-live)..."
    if chroot "$DEST" dracut --force \
            --add "dmsquash-live" \
            --omit "resume" \
            "/boot/initramfs-${_KVER_LIVE}-live.img" \
            "$_KVER_LIVE" 2>/dev/null; then
        echo "[DC] ✓ live initramfs regenerated: initramfs-${_KVER_LIVE}-live.img"
        INITRD="$_INITRD_LIVE"
    else
        echo "[DC] WARN — dracut-live regeneration failed, using existing initramfs"
    fi
  fi
fi
set -e

# Verify PHYSICAL existence of files (not just that variables are non-empty)
if [ -z "$KERNEL" ] || [ ! -f "$KERNEL" ]; then
  echo "$MSG_ERR_KERNEL"
  echo "[DC] DEBUG — Kernel not found: '$KERNEL'"
  echo "[DC] DEBUG — Family:             '$DC_FAMILY'"
  echo "[DC] DEBUG — Boot contents:      $(ls "$DEST"/boot/ 2>/dev/null)"
  exit 1
fi

if [ -z "$INITRD" ] || [ ! -f "$INITRD" ]; then
  echo "[DC] WARNING — initramfs not found: '$INITRD'"
  echo "[DC] DEBUG — Boot contents: $(ls "$DEST"/boot/ 2>/dev/null)"
  # Last attempt: use any available initramfs
  INITRD=$(ls "$DEST"/boot/initramfs-*.img "$DEST"/boot/initrd* 2>/dev/null | grep -v rescue | sort -V | tail -n1)
  if [ -z "$INITRD" ] || [ ! -f "$INITRD" ]; then
    echo "$MSG_ERR_KERNEL"
    echo "[DC] No initramfs found in $DEST/boot/"
    exit 1
  fi
  echo "[DC] ✓ initramfs found as fallback: $(basename "$INITRD")"
fi

mkdir -p "$ISO_DIR/live"
cp "$KERNEL" "$ISO_DIR/live/vmlinuz"

# ── Verify and generate initramfs with archiso hook (Arch only) ──────────────
# CHROOT_ARCH_EOF installs mkinitcpio + mkinitcpio-archiso and regenerates.
# On Garuda dracut may win and leave the original dracut initramfs.
# Verify that the initramfs contains the archiso hook; if not, generate it
# on the HOST with mkinitcpio installed on the fly.
# Signature dracut: contains "rdsosreport" or "dracut" in CPIO listing.
# Signature mkinitcpio+archiso: lsinitcpio shows "hooks/archiso".
if [ "${DC_FAMILY:-arch}" = "arch" ]; then
    _HAS_ARCHISO=false

    # Fix 33 — Primary check: mkinitcpio.conf in target (written by DC itself)
    # More reliable than lsinitcpio which may return empty output on initramfs
    # zstd multi-part or with archiso.conf drop-in (EndeavourOS, Arch vanilla).
    if grep -qE '^HOOKS=.*archiso' "$DEST/etc/mkinitcpio.conf" 2>/dev/null; then
        _HAS_ARCHISO=true
        echo "[DC] archiso hook detected via mkinitcpio.conf in target"
    fi

    # Secondary check: lsinitcpio (only if primary check fails)
    if ! $_HAS_ARCHISO && command -v lsinitcpio >/dev/null 2>&1 && [ -f "$INITRD" ]; then
        lsinitcpio "$INITRD" 2>/dev/null | grep -qE "(hooks/archiso|/archiso$)" && _HAS_ARCHISO=true
        $_HAS_ARCHISO && echo "[DC] archiso hook detected via lsinitcpio"
    fi

    if ! $_HAS_ARCHISO; then
        echo "[DC] ERROR: target initramfs missing archiso hook"
        echo "[DC] ERROR: HOST fallback disabled for safety on Arch/EndeavourOS"
        echo "[DC] ERROR: fix the target in $DEST without touching the host system"
        exit 1
    else
        echo "[DC] ✓ initramfs contains archiso hook"
    fi
fi

cp "$INITRD" "$ISO_DIR/live/initrd.img"

# Fedora dracut dmsquash-live looks for squashfs in /LiveOS/squashfs.img
# Debian live-boot looks in /live/filesystem.squashfs
# Create both structures for cross-distro compatibility
if [ "${DC_FAMILY:-arch}" = "fedora" ] || [ "${DC_FAMILY:-arch}" = "opensuse" ]; then
    mkdir -p "$ISO_DIR/LiveOS"
    echo "[DC] Fedora: LiveOS directory structure created (squashfs.img will be linked after mksquashfs)"
fi

# ── Fix fstab for live system ────────────────────────────────────────────────
# The host fstab contains UUIDs for /boot, /boot/efi, swap that do not exist
# in the live environment → systemd-remount-fs.service fails in a loop.
# Replace with a minimal fstab suitable for the live system.
echo "[DC] Writing minimal live fstab to $DEST/etc/fstab..."
cat > "$DEST/etc/fstab" << 'LIVEFSTAB'
# /etc/fstab — live system (generated by DistroClone)
# No physical disk: rootfs is in RAM (squashfs + overlay)
proc      /proc     proc    defaults              0 0
sysfs     /sys      sysfs   defaults              0 0
devpts    /dev/pts  devpts  gid=5,mode=620        0 0
tmpfs     /run      tmpfs   defaults              0 0
tmpfs     /tmp      tmpfs   defaults,nosuid,nodev,mode=1777  0 0
LIVEFSTAB
echo "[DC] ✓ live fstab written"

echo "  ✓ $MSG_KERNEL: $(basename "$KERNEL") [$DC_FAMILY]"
echo "  ✓ Initrd:  $(basename "$INITRD")"
echo "  ✓ Boot params: $DC_BOOT_PARAMS"

############################################
# [21/30] PAUSE FOR MANUAL EDITS
############################################
log_msg "$MSG_STEP21"

MANUAL_EDIT=false

# Regenerate DC logo for dialog
TEMP_LOGO="$(get_dc_logo 128)"

if [ "$GUI_TOOL" = "yad" ]; then
        yad --question \
        --title="$MSG_MANEDIT_TITLE" \
        --window-icon="$TEMP_LOGO" \
        ${TEMP_LOGO:+--image="$TEMP_LOGO"} \
        --text="$MSG_MANEDIT_HEADING\n\n$MSG_MANEDIT_TEXT\n\n<b>$MSG_MANEDIT_PATH</b> $DEST\n\n$MSG_MANEDIT_SELECT" \
        --button="$MSG_BTN_EDIT:0" \
        --button="$MSG_BTN_CONTINUE:1" \
        --width=500 --height=200 \
        --fixed \
        --center 2>/dev/null && MANUAL_EDIT=true

else
    zenity --question \
        --title="$MSG_MANEDIT_TITLE" \
        --text="$MSG_MANEDIT_ZENITY ($DEST)" \
        --ok-label="$MSG_BTN_YES" --cancel-label="$MSG_BTN_NO" \
        --width=400 2>/dev/null && MANUAL_EDIT=true
fi

if [ "$MANUAL_EDIT" = true ]; then
    echo ""
    echo "=========================================="
    echo "  $MSG_PAUSE_TITLE"
    echo "=========================================="
    echo ""
    echo "  $MSG_PAUSE_AVAILABLE"
    echo "  → $DEST"
    echo ""
    echo "  $MSG_PAUSE_CHROOT"
    echo "  sudo chroot $DEST /bin/bash"
    echo ""
    echo "  $MSG_PAUSE_DONE"
    echo ""
    echo "=========================================="
    read -p "$MSG_PAUSE_ENTER "
    echo "$MSG_PAUSE_SHOOTING"
fi

############################################
# [22/30] SQUASHFS COMPRESSION SELECTION
############################################
log_msg "$MSG_STEP22"

# Se YAD è stato usato, la compressione è già impostata
# Altrimenti, chiedi all'utente con Zenity o terminale
if [ "$GUI_TOOL" != "yad" ]; then
    SQUASH_OPTS=""
    COMP_LABEL="standard"
    
    if command -v zenity >/dev/null 2>&1; then
        CHOICE=$(zenity --list \
            --title="$MSG_COMP_SELECT_TITLE" \
            --text="$MSG_COMP_SELECT_TEXT" \
            --radiolist \
            --column="$MSG_COMP_USING" --column="$MSG_COMP_CODE" --column="$MSG_COMP_DESCRIPTION" \
            TRUE  "F" "$MSG_COMP_FAST_DESC" \
            FALSE "S" "$MSG_COMP_STD_DESC" \
            FALSE "M" "$MSG_COMP_MAX_DESC" \
            --height=320 --width=500) || CHOICE="S"
    else
        # Terminal: prompt manually
        echo ""
        echo "$MSG_TTY_SELECT_COMP"
        echo "  F = $MSG_TTY_COMP_FAST"
        echo "  S = $MSG_TTY_COMP_STD"
        echo "  M = $MSG_TTY_COMP_MAX"
        read -p "$MSG_TTY_CHOICE: " -n 1 -r CHOICE
        echo ""
        [ -z "$CHOICE" ] && CHOICE="S"
    fi
    
    case "$CHOICE" in
        F|f)
            SQUASHFS_COMP="lz4"
            ;;
        M|m)
            SQUASHFS_COMP="xz-bcj"
            ;;
        *)
            SQUASHFS_COMP="xz"
            ;;
    esac
fi

# Configure squashfs options based on selection
SQUASH_OPTS=""
COMP_LABEL="standard"

case "$SQUASHFS_COMP" in
  lz4)
    echo "  $MSG_COMP_FAST_LOG"
    SQUASH_OPTS="-comp lz4"
    COMP_LABEL="fast"
    ;;
  xz-bcj)
    echo "  $MSG_COMP_MAX_LOG"
    SQUASH_OPTS="-comp xz -Xbcj x86 -Xdict-size 100% -b 1M"
    COMP_LABEL="max"
    ;;
  *)
    echo "  $MSG_COMP_STD_LOG"
    SQUASH_OPTS="-comp xz -b 256K -Xdict-size 100%"
    COMP_LABEL="standard"
    ;;
esac

############################################
# [23/30] SQUASHFS CREATION
############################################
log_msg "$MSG_STEP23 ($COMP_LABEL)"

# Squashfs path depends on the distro family
if [ "${DC_FAMILY:-arch}" = "fedora" ] || [ "${DC_FAMILY:-arch}" = "opensuse" ]; then
    _SQUASHFS_PATH="$ISO_DIR/LiveOS/squashfs.img"
elif [ "${DC_FAMILY:-arch}" = "arch" ]; then
    # Arch (including Garuda): always archiso → arch/<machine>/airootfs.sfs
    # CHROOT_ARCH_EOF uses mkinitcpio + archiso hooks for all Arch systems.
    _ARCH_MACHINE=$(uname -m)
    mkdir -p "$ISO_DIR/arch/${_ARCH_MACHINE}"
    _SQUASHFS_PATH="$ISO_DIR/arch/${_ARCH_MACHINE}/airootfs.sfs"
else
    _SQUASHFS_PATH="$ISO_DIR/live/filesystem.squashfs"
fi
echo "[DC] Squashfs path: $_SQUASHFS_PATH"

# Ensure /tmp exists in DEST as empty directory with sticky bit
# (mkinitcpio in Calamares target chroot requires it)
find "$DEST/tmp" -mindepth 1 -delete 2>/dev/null || true
mkdir -p "$DEST/tmp"
chmod 1777 "$DEST/tmp"
echo "[DC] ✓ \$DEST/tmp created empty (sticky 1777) for mkinitcpio in target"

# Snapper config: exclude ONLY on openSUSE (destined for recreation via
# dc-firstboot). On Arch (CachyOS) preserve the config for grub-btrfs.
_DC_SQUASH_SNAPPER_EXCL=""
if [ "${DC_FAMILY:-}" = "opensuse" ]; then
    _DC_SQUASH_SNAPPER_EXCL="-e etc/snapper/configs/root"
fi

mksquashfs "$DEST" "$_SQUASHFS_PATH" \
  $SQUASH_OPTS \
  -e var/cache \
  -e var/tmp \
  -e var/log \
  -e usr/share/doc \
  -e usr/share/info \
  -e root/.cache \
  -e home/*/.cache \
  -e home/*/.local/share/Trash \
  -e .snapshots \
  -e var/lib/snapper/snapshots \
  $_DC_SQUASH_SNAPPER_EXCL \
  -wildcards

echo "  $MSG_SQUASH_SIZE: $(du -h "$_SQUASHFS_PATH" | cut -f1)"

# [23b] STATIC TEST — squashfs valid
_SQ_MB=$(du -m "$_SQUASHFS_PATH" 2>/dev/null | cut -f1)
if [ "${_SQ_MB:-0}" -lt 100 ]; then
    echo "[TEST WARN] Squashfs too small (${_SQ_MB:-0} MB) — likely corrupt build"
elif ! file "$_SQUASHFS_PATH" 2>/dev/null | grep -qi squash; then
    echo "[TEST WARN] $_SQUASHFS_PATH does not appear to be a valid squashfs filesystem"
else
    echo "[DC][23b] Static test squashfs: ${_SQ_MB} MB OK"
fi

############################################
# [24/30] GRUB configuration
############################################
log_msg "$MSG_STEP24"

mkdir -p "$ISO_DIR/boot/grub"

# ── GRUB Background + Dark Noir theme ───────────────────────────────────────
# The distro name text is NOT baked into the PNG image: it is handled
# by the GRUB theme (label widget) positioned ABOVE the boot_menu widget.
# This avoids the title/menu overlap that occurs with background_image.
_THEME_DIR="$ISO_DIR/boot/grub/themes/distroClone"
mkdir -p "$_THEME_DIR"

if [ -f "distroClone-grub.png" ]; then
    cp "distroClone-grub.png" "$ISO_DIR/boot/grub/grub.png"
    cp "distroClone-grub.png" "$_THEME_DIR/background.png"
    echo "  $MSG_GRUB_CUSTOM"
else
    if command -v $IM_CMD >/dev/null 2>&1; then
        # Noir Obsidian gradient — top deep navy, bottom near-black.
        # -depth 8 -type TrueColor -define png:color-type=2 REQUIRED:
        # ImageMagick 7 on Arch generates RGBA/16-bit that GRUB cannot handle (rainbow).
        $IM_CMD -size 1024x768 gradient:'#050d22'-'#020509' \
            -depth 8 -type TrueColor \
            -define png:color-type=2 -define png:bit-depth=8 \
            "$_THEME_DIR/background.png" 2>/dev/null \
        && cp "$_THEME_DIR/background.png" "$ISO_DIR/boot/grub/grub.png" \
        || true
        echo "  $MSG_GRUB_DEFAULT"
    else
        echo "  $MSG_GRUB_NOCONVERT"
    fi
fi

# unicode.pf2: path varies by distro (grub vs grub2, openSUSE uses grub2/)
# Look first on HOST, then inside $DEST (cloned rootfs — always present)
_UNICODE_PF2=""
for _up in \
    /usr/share/grub/unicode.pf2 \
    /usr/share/grub2/unicode.pf2 \
    /usr/lib/grub/x86_64-efi/unicode.pf2 \
    /usr/lib/grub2/x86_64-efi/unicode.pf2 \
    /boot/grub/unicode.pf2 \
    /boot/grub2/unicode.pf2 \
    "$DEST/usr/share/grub2/unicode.pf2" \
    "$DEST/usr/share/grub/unicode.pf2" \
    "$DEST/usr/lib/grub/x86_64-efi/unicode.pf2" \
    "$DEST/usr/lib/grub2/x86_64-efi/unicode.pf2"; do
    [ -f "$_up" ] && [ -s "$_up" ] && _UNICODE_PF2="$_up" && break
done
if [ -n "$_UNICODE_PF2" ]; then
    cp "$_UNICODE_PF2" "$ISO_DIR/boot/grub/unicode.pf2"
    echo "  [GRUB] unicode.pf2 copied from: $_UNICODE_PF2"
else
    # Fallback: generate with grub-mkfont / grub2-mkfont if available
    for _mkcmd in grub-mkfont grub2-mkfont; do
        if command -v "$_mkcmd" >/dev/null 2>&1; then
            "$_mkcmd" --output="$ISO_DIR/boot/grub/unicode.pf2" \
                /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf 2>/dev/null || \
            "$_mkcmd" --output="$ISO_DIR/boot/grub/unicode.pf2" \
                /usr/share/fonts/dejavu/DejaVuSans.ttf 2>/dev/null || true
            [ -f "$ISO_DIR/boot/grub/unicode.pf2" ] && break
        fi
    done
    if [ -f "$ISO_DIR/boot/grub/unicode.pf2" ]; then
        echo "  [GRUB] unicode.pf2 generated with grub-mkfont"
    else
        echo "  [GRUB] WARN: unicode.pf2 not found — GRUB without font (non-critical)"
        touch "$ISO_DIR/boot/grub/unicode.pf2"  # placeholder per evitare errori grub.cfg
    fi
fi

# ── GRUB theme fonts: DCTitle serif (elegant), DCMenu sans, DCSmall subtitle ──
# Prefer DejaVuSerif-Bold for DCTitle: refined look close to Cinzel
# of the Noir Obsidian theme. Fallback to DejaVuSans-Bold if serif is absent.
# DCSmall (13pt) usato per il subtitle "GRUB Boot Menu" in alto.
_TITLE_FONT="Unknown Regular 16"
_MENU_FONT="Unknown Regular 16"
_SMALL_FONT="Unknown Regular 16"

for _mkcmd in grub-mkfont grub2-mkfont; do
    command -v "$_mkcmd" >/dev/null 2>&1 || continue

    # DCTitle: serif bold 32pt — try serif first, fallback to sans-bold
    for _bold in \
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf" \
        "/usr/share/fonts/dejavu/DejaVuSerif-Bold.ttf" \
        "/usr/share/fonts/TTF/DejaVuSerif-Bold.ttf" \
        "/usr/share/fonts/dejavu-serif/DejaVuSerif-Bold.ttf" \
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" \
        "/usr/share/fonts/truetype/DejaVuSans-Bold.ttf" \
        "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf" \
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf" \
        "/usr/share/fonts/dejavu-sans/DejaVuSans-Bold.ttf" \
        "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf"; do
        [ -f "$_bold" ] || continue
        "$_mkcmd" -s 32 --name "DCTitle" "$_bold" \
            -o "$_THEME_DIR/title.pf2" 2>/dev/null \
        && _TITLE_FONT="DCTitle" \
        && echo "  [GRUB] title.pf2 generated (DCTitle 32pt from $_bold)" \
        && break
    done

    # DCMenu: sans regular 15pt — menu entries
    for _reg in \
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/truetype/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/TTF/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu-sans/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"; do
        [ -f "$_reg" ] || continue
        "$_mkcmd" -s 15 --name "DCMenu" "$_reg" \
            -o "$_THEME_DIR/menu.pf2" 2>/dev/null \
        && _MENU_FONT="DCMenu" \
        && echo "  [GRUB] menu.pf2 generated (DCMenu 15pt from $_reg)" \
        && break
    done

    # DCSmall: sans regular 12pt — subtitle and muted labels
    for _reg in \
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/truetype/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu/DejaVuSans.ttf" \
        "/usr/share/fonts/TTF/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu-sans/DejaVuSans.ttf" \
        "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf"; do
        [ -f "$_reg" ] || continue
        "$_mkcmd" -s 12 --name "DCSmall" "$_reg" \
            -o "$_THEME_DIR/small.pf2" 2>/dev/null \
        && _SMALL_FONT="DCSmall" \
        && echo "  [GRUB] small.pf2 generated (DCSmall 12pt from $_reg)" \
        && break
    done

    break   # use only the first grub-mkfont found
done

# ── theme.txt: title label at 8%, subtitle label at 17%, boot_menu at 24% ──
# Separate layout: title ALWAYS above menu, never overlapping.
cat > "$_THEME_DIR/theme.txt" << GRUBTHEME
# DistroClone — Noir Obsidian (live ISO boot)
# Elegant serif typography, dot indicator, refined layout.
desktop-image: "background.png"
desktop-color: "#030912"
message-font: "${_SMALL_FONT}"
message-color: "#506090"
message-bg-color: "#030912"

# ── Short accent line (simulated with label) ──
+ label {
    top = 8%
    left = 37%
    width = 26%
    align = "left"
    text = "________________"
    font = "${_SMALL_FONT}"
    color = "#1a3a8f"
}

# ── Subtitle: "GRUB Boot Menu" — small, muted ──
+ label {
    top = 11%
    left = 0%
    width = 100%
    align = "center"
    text = "GRUB Boot Menu"
    font = "${_SMALL_FONT}"
    color = "#2a4070"
}

# ── Distro name: large, serif bold, white ──
+ label {
    top = 16%
    left = 0%
    width = 100%
    align = "center"
    text = "${DISTRO_NAME}"
    font = "${_TITLE_FONT}"
    color = "#ffffff"
}

# ── Dot separator ──
+ label {
    top = 26%
    left = 0%
    width = 100%
    align = "center"
    text = "·  ·  ·"
    font = "${_SMALL_FONT}"
    color = "#1a3060"
}

# ── Boot menu: muted blue-gray entries, selected white ──
+ boot_menu {
    left = 20%
    top = 30%
    width = 60%
    height = 46%
    item_font = "${_MENU_FONT}"
    item_color = "#3a5280"
    selected_item_color = "#ffffff"
    item_height = 38
    item_padding = 16
    item_spacing = 1
}

# ── Progress bar: ultra thin, ghost blue, no text ──
+ progress_bar {
    id = "__timeout__"
    left = 30%
    top = 83%
    width = 40%
    height = 2
    show_text = false
    fg_color = "#1a3aaa"
    bg_color = "#060e28"
    border_color = "#0a1840"
}

# ── Auto-boot label below the bar ──
+ label {
    top = 86%
    left = 0%
    width = 100%
    align = "center"
    text = "auto boot"
    font = "${_SMALL_FONT}"
    color = "#1a2a50"
}
GRUBTHEME
echo "  [GRUB] Noir Obsidian theme (live): $_THEME_DIR/theme.txt"
echo "  [GRUB] title=${_TITLE_FONT}  menu=${_MENU_FONT}  small=${_SMALL_FONT}"

cat > "$ISO_DIR/boot/grub/grub.cfg" << EOF
# Load required modules
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod all_video
insmod font
insmod png
insmod gfxterm
insmod gfxterm_background

# Find the ISO partition by label
search --no-floppy --set=root --label ${ISO_LABEL}


# Enable dark graphical terminal
# Required order: loadfont unicode → gfxterm → loadfont theme → set theme
if loadfont /boot/grub/unicode.pf2 ; then
    set gfxmode=1024x768,auto
    terminal_output gfxterm
fi
if [ -f /boot/grub/themes/distroClone/title.pf2 ]; then
    loadfont /boot/grub/themes/distroClone/title.pf2
fi
if [ -f /boot/grub/themes/distroClone/menu.pf2 ]; then
    loadfont /boot/grub/themes/distroClone/menu.pf2
fi
if [ -f /boot/grub/themes/distroClone/small.pf2 ]; then
    loadfont /boot/grub/themes/distroClone/small.pf2
fi
if [ -f /boot/grub/themes/distroClone/theme.txt ]; then
    set theme=/boot/grub/themes/distroClone/theme.txt
elif background_image /boot/grub/grub.png ; then
    set color_normal=light-gray/black
    set color_highlight=white/dark-gray
fi
# Terminal colors for boot messages (after entry selection: "Booting...", "Loading...")
# The theme handles the menu; these colors apply to the kernel boot screen.
# black = pure black, light-gray = readable text on black background.
set color_normal=light-gray/black
set color_highlight=white/dark-gray

set default=0
set timeout=5

menuentry "$MSG_GRUB_TRY ${DISTRO_NAME}" {
    linux /live/vmlinuz ${DC_BOOT_PARAMS}
    initrd /live/initrd.img
}

menuentry "${DISTRO_NAME} $MSG_GRUB_SAFE" {
    linux /live/vmlinuz ${DC_BOOT_PARAMS} nomodeset
    initrd /live/initrd.img
}

menuentry "$MSG_GRUB_INSTALL ${DISTRO_NAME}" {
    linux /live/vmlinuz ${DC_BOOT_PARAMS} systemd.unit=multi-user.target
    initrd /live/initrd.img
}

menuentry "UEFI Firmware Settings" {
    setparams 'UEFI Firmware Settings'
    fwsetup
}

EOF

# [24b] STATIC TEST — grub.cfg boot params corretti per la distro
_GRUB_CFG="$ISO_DIR/boot/grub/grub.cfg"
_GRUB_OK=1
case "${DC_FAMILY:-arch}" in
  arch)
    case "${DC_LIVE_STACK:-archiso}" in
      archiso)
        grep -q "archisolabel=${ISO_LABEL}" "$_GRUB_CFG" \
            || { echo "[TEST WARN] grub.cfg: archisolabel=${ISO_LABEL} missing"; _GRUB_OK=0; }
        grep -q "archisobasedir=arch" "$_GRUB_CFG" \
            || { echo "[TEST WARN] grub.cfg: archisobasedir=arch missing"; _GRUB_OK=0; }
        ;;
      dracut-live)
        grep -q "rd.live.image" "$_GRUB_CFG" \
            || { echo "[TEST WARN] grub.cfg: rd.live.image missing"; _GRUB_OK=0; }
        grep -q "CDLABEL=${ISO_LABEL}" "$_GRUB_CFG" \
            || { echo "[TEST WARN] grub.cfg: CDLABEL=${ISO_LABEL} missing"; _GRUB_OK=0; }
        ;;
    esac
    ;;
  fedora|opensuse)
    grep -qE "root=live:|rd.live.image" "$_GRUB_CFG" \
        || { echo "[TEST WARN] grub.cfg: live boot params (root=live: / rd.live.image) missing"; _GRUB_OK=0; }
    ;;
esac
[ "$_GRUB_OK" -eq 1 ] && echo "[DC][24b] Static test grub.cfg: OK" \
                       || echo "[DC][24b] Static test grub.cfg: WARN — see above"

############################################
# [25/30] GRUB EFI binaries
############################################
log_msg "$MSG_STEP25"

# Note: video_fb, efi_gop and efi_uga are essential for UEFI/VirtualBox
# Fedora uses grub2-mkstandalone, Debian uses grub-mkstandalone
_GRUB_MKSTANDALONE=""
for _gcmd in grub-mkstandalone grub2-mkstandalone; do
    command -v "$_gcmd" >/dev/null 2>&1 && _GRUB_MKSTANDALONE="$_gcmd" && break
done
[ -z "$_GRUB_MKSTANDALONE" ] && { echo "[ERROR] grub-mkstandalone/grub2-mkstandalone not found"; exit 1; }
"$_GRUB_MKSTANDALONE" -O x86_64-efi \
    --modules="part_gpt part_msdos fat iso9660 search search_label search_fs_file search_fs_uuid all_video video_fb efi_gop efi_uga font gfxterm gfxterm_background png echo test" \
    --output="$ISO_DIR/EFI/BOOT/BOOTX64.EFI" \
    "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

############################################
# [26/30] EFI SYSTEM PARTITION IMAGE
############################################
log_msg "$MSG_STEP26"
(
  cd "$ISO_DIR" || exit 1
  dd if=/dev/zero of=efiboot.img bs=1M count=20 status=none
  mkfs.vfat -n 'EFIBOOT' efiboot.img >/dev/null
  mmd -i efiboot.img ::/EFI ::/EFI/BOOT
  mcopy -i efiboot.img EFI/BOOT/BOOTX64.EFI ::/EFI/BOOT/
  echo "[OK] efiboot.img: $(du -h efiboot.img | cut -f1)"
)

############################################
# [27/30] ISOLINUX BIOS
############################################
log_msg "$MSG_STEP27"

mkdir -p "$ISO_DIR/isolinux"

cat > "$ISO_DIR/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT live

MENU TITLE ${DISTRO_NAME} Boot Menu

LABEL live
  MENU LABEL ^${DISTRO_NAME} Live
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img ${DC_BOOT_PARAMS}

LABEL install
  MENU LABEL ^Install ${DISTRO_NAME}
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img ${DC_BOOT_PARAMS}

LABEL debug
  MENU LABEL Live (^Debug)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img ${DC_BOOT_PARAMS} systemd.log_level=debug

LABEL failsafe
  MENU LABEL Live (^Failsafe)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd.img ${DC_BOOT_PARAMS} noapic noacpi
EOF

# Auto-detect paths Syslinux
for file in isolinux.bin isohdpfx.bin; do
  found=false
  for dir in /usr/lib/ISOLINUX /usr/lib/syslinux/bios /usr/share/syslinux /usr/lib/syslinux/modules/bios; do
    if [ -f "$dir/$file" ]; then
      cp "$dir/$file" "$ISO_DIR/isolinux/"
      echo "[OK] Copied $file from $dir"
      found=true
      break
    fi
  done
  if [ "$found" = false ]; then
    echo "WARN: $file not found, skip (not critical for UEFI)"
  fi
done

# C32 modules (multiple fallback paths)
# Fedora: /usr/share/syslinux/ — Debian/Ubuntu: /usr/lib/syslinux/modules/bios/
cp /usr/lib/syslinux/modules/bios/*.c32 "$ISO_DIR/isolinux/" 2>/dev/null || \
cp /usr/lib/syslinux/bios/*.c32         "$ISO_DIR/isolinux/" 2>/dev/null || \
cp /usr/share/syslinux/*.c32            "$ISO_DIR/isolinux/" 2>/dev/null || true
# Verify ldlinux.c32 (essential for ISOLINUX)
if [ ! -f "$ISO_DIR/isolinux/ldlinux.c32" ]; then
    echo "[WARN] ldlinux.c32 not found in standard paths — ISO not bootable in BIOS mode"
fi

############################################
# [28/30] FINAL HYBRID ISO
############################################
log_msg "$MSG_STEP28"

ISO_SIZE=$(du -sm "$ISO_DIR" | cut -f1)
CYLINDERS=$((ISO_SIZE * 2 / 255 / 63 + 1))

if [ $CYLINDERS -gt 1024 ]; then
  echo "$MSG_WARN_BIGISO ($ISO_SIZE MB)"
fi

# Check isolinux availability for legacy BIOS boot
_ISOHDPFX="$ISO_DIR/isolinux/isohdpfx.bin"
_ISOLINUX_BIN="$ISO_DIR/isolinux/isolinux.bin"
_XORRISO_RC=0

if [ -f "$_ISOHDPFX" ] && [ -f "$_ISOLINUX_BIN" ]; then
    echo "[DC] BIOS boot available → hybrid BIOS+UEFI ISO"
    xorriso -as mkisofs \
      -iso-level 3 \
      -full-iso9660-filenames \
      -volid "$ISO_LABEL" \
      -joliet -joliet-long \
      -rational-rock \
      --mbr-force-bootable \
      -partition_offset 16 \
      -isohybrid-mbr "$_ISOHDPFX" \
      -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
      --eltorito-catalog isolinux/isolinux.cat \
      -eltorito-alt-boot \
        -e efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
      -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$ISO_DIR/efiboot.img" \
      -output "$LIVE_DIR/$ISO_NAME" \
      "$ISO_DIR" \
      2>&1 | tee /tmp/xorriso.log | grep -E "(Warning|ERROR)" || true
    _XORRISO_RC=${PIPESTATUS[0]}
else
    echo "[DC] WARN: isolinux not found → UEFI-only ISO (no legacy BIOS boot)"
    # Note: NO -isohybrid-gpt-basdat / -append_partition → they create a GPT
    # hybrid structure incompatible with VirtualBox (VERR_NOT_SUPPORTED).
    # El-Torito EFI (-e efiboot.img) is sufficient for UEFI boot from optical/VM.
    xorriso -as mkisofs \
      -iso-level 3 \
      -full-iso9660-filenames \
      -volid "$ISO_LABEL" \
      -joliet -joliet-long \
      -rational-rock \
      -eltorito-alt-boot \
        -e efiboot.img \
        -no-emul-boot \
      -output "$LIVE_DIR/$ISO_NAME" \
      "$ISO_DIR" \
      2>&1 | tee /tmp/xorriso.log | grep -E "(Warning|ERROR)" || true
    _XORRISO_RC=${PIPESTATUS[0]}
fi

if [ "$_XORRISO_RC" -ne 0 ]; then
    echo "[ERROR] xorriso failed (exit $_XORRISO_RC) — log: /tmp/xorriso.log"
    tail -20 /tmp/xorriso.log
    exit 1
fi

############################################
# [29/30] FINAL VERIFICATION
############################################
log_msg "$MSG_STEP29"

if [ -f "$LIVE_DIR/$ISO_NAME" ]; then
  ISO_SIZE_FINAL=$(du -h "$LIVE_DIR/$ISO_NAME" | cut -f1)
  # [29b] STATIC TEST — ISO valid
  _ISO_MB=$(du -m "$LIVE_DIR/$ISO_NAME" 2>/dev/null | cut -f1)
  if [ "${_ISO_MB:-0}" -lt 200 ]; then
      echo "[TEST WARN] ISO too small (${_ISO_MB:-0} MB) — likely failed build"
  elif ! file "$LIVE_DIR/$ISO_NAME" 2>/dev/null | grep -qi "ISO 9660"; then
      echo "[TEST WARN] $ISO_NAME does not appear to be a valid ISO 9660 image"
  else
      echo "[DC][29b] Static test ISO: ${_ISO_MB} MB — formato OK"
  fi

  echo ""
  echo "=========================================="
  echo "$MSG_ISO_SUCCESS"
  echo "=========================================="
  echo "  $MSG_FILE: $LIVE_DIR/$ISO_NAME"
  echo "  $MSG_SIZE: $ISO_SIZE_FINAL"
  
echo "$MSG_MD5_GEN"

cd "$LIVE_DIR"
md5sum "$ISO_NAME" > "$ISO_NAME.md5"
sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"

echo "$MSG_CREATED: $LIVE_DIR/$ISO_NAME.md5 & $LIVE_DIR/$ISO_NAME.sha256"
  
  echo "=========================================="
  echo ""
  echo "$MSG_TEST_ISO"
  echo "  1. $MSG_TEST_VBOX $ISO_NAME"
  echo "  2. qemu-system-x86_64 -enable-kvm -m 4096 -cdrom $LIVE_DIR/$ISO_NAME -boot d"
  echo "  3. ${MSG_TEST_USB}$LIVE_DIR/$ISO_NAME of=/dev/sdX bs=4M status=progress"
  echo ""
  
############################################
  # [30/30] HOST SYSTEM CLEANUP
############################################
# Save logo to /tmp BEFORE cleanup
  FINAL_LOGO="$(get_dc_logo 128)"
  if [ -n "$FINAL_LOGO" ] && [ -f "$FINAL_LOGO" ]; then
      cp "$FINAL_LOGO" /tmp/distroClone-final-logo.png 2>/dev/null
      FINAL_LOGO="/tmp/distroClone-final-logo.png"
  fi
log_msg "$MSG_STEP30"
  
  # Remove working directory
  echo "$MSG_REMOVING_DIR"
  # Unmount residuals before rm
  umount -lR /mnt/${DISTRO_ID}_live/rootfs 2>/dev/null || true
  sleep 2
  rm -rf /mnt/${DISTRO_ID}_live/rootfs 2>/dev/null || true
  rm -rf /mnt/${DISTRO_ID}_live/iso 2>/dev/null || true
  # Fix 50: remove host pacman cache — used only during Arch chroot, not part
  # of the ISO (it is in host /mnt/, not in $DEST). May waste hundreds of MB.
  rm -rf /mnt/.distroclone-pacman-cache 2>/dev/null || true
  echo "[DC] ✓ Host pacman cache removed"
  
  # Close log window
  exec 3>&- 2>/dev/null || true
  if [ -n "$LOG_PID" ] && kill -0 "$LOG_PID" 2>/dev/null; then
      kill "$LOG_PID" 2>/dev/null
      wait "$LOG_PID" 2>/dev/null || true
  fi

  # Final success dialog
  _DC_MSG_TEST="${MSG_TEST_TEXT//__ISO__/$LIVE_DIR\/$ISO_NAME}"
  if [ "$GUI_TOOL" = "yad" ]; then
      TEMP_LOGO="$FINAL_LOGO"
      yad --info \
          --title="$MSG_COMPLETED_TITLE" \
          ${TEMP_LOGO:+--window-icon="$TEMP_LOGO"} \
          ${TEMP_LOGO:+--image="$TEMP_LOGO"} \
          --text="$MSG_ISO_SUCCESS_BIG\n\n<b>$MSG_FILE:</b> $LIVE_DIR/$ISO_NAME\n<b>$MSG_SIZE:</b> $ISO_SIZE_FINAL\n\n${_DC_MSG_TEST}$LIVE_DIR/$ISO_NAME of=/dev/sdX bs=4M status=progress" \
          --button="OK:0" \
          --width=510 --height=200 \
          --fixed \
          --center \
          2>/dev/null
  fi
  
  
else
  echo ""
  echo "=========================================="
  echo "$MSG_ISO_ERROR"
  echo "=========================================="

  # Fix 50: cleanup host pacman cache also on error
  rm -rf /mnt/.distroclone-pacman-cache 2>/dev/null || true

  # Close log window
  exec 3>&- 2>/dev/null || true
  if [ -n "$LOG_PID" ] && kill -0 "$LOG_PID" 2>/dev/null; then
      kill "$LOG_PID" 2>/dev/null
      wait "$LOG_PID" 2>/dev/null || true
  fi

  if [ "$GUI_TOOL" = "yad" ]; then
      yad --error \
          --title="$MSG_ERROR_TITLE" \
          --text="$MSG_ISO_FAIL_BIG" \
          --button="OK:0" \
          --width=400 --height=200 \
          --fixed
          --center \
          2>/dev/null
  fi

  exit 1
fi
