DistroClone Cross-Distro
Analisi Tecnica v1.3.6

Come funziona davvero il framework Bash che clona qualsiasi sistema Linux live in una ISO installabile, con supporto nativo per sei famiglie di distribuzioni.

Circa 12.000 righe Bash - 9 file principali - 7+ distro supportate - 6 lingue UI - 30 step pipeline - 3 backend initramfs


01. Panoramica e design philosophy

DistroClone Cross-Distro nasce da un problema reale: gli strumenti di clonazione Linux esistenti (penguins-eggs, Remastersys, Refracta) sono mono-famiglia. Funzionano su Debian, o su Arch, non su entrambi. DistroClone risolve questo con un'architettura plugin-based che separa la core pipeline invariante dagli override family-specifici.

Il progetto è distribuito come singolo AppImage autocontenuto (v1.3.6). Non richiede installazione: scarichi, chmod +x, esegui come root. Le dipendenze host vengono installate automaticamente al primo avvio tramite il package manager nativo della distro rilevata.

Idea centrale: ogni distribuzione Linux, per quanto diversa nella superficie, condivide la stessa struttura di fondo — rootfs + kernel + initramfs + bootloader. DistroClone astrae questa struttura e la impacchetta in una ISO installabile via Calamares, indipendentemente dalla famiglia di partenza.

Distro supportate ufficialmente

Famiglia Arch: ArchLinux, CachyOS, EndeavourOS, Garuda Linux, Manjaro
Famiglia Fedora: Fedora, AlmaLinux, Rocky Linux, Nobara
Famiglia openSUSE: openSUSE Tumbleweed, Leap, SLES


02. Architettura del progetto

Il progetto si articola in due contesti di esecuzione distinti con responsabilità separate.

Contesto 1 — Host live: DistroClone.sh gira sull'host live, clona il rootfs via rsync, assembla squashfs e ISO.

Contesto 2 — Chroot Calamares: calamares-config.sh gira dentro il chroot dell'installazione, configura bootloader, initramfs e servizi del sistema installato.

```
# Flusso ad alto livello

AppImage (entry point)
    |
    +-- distro-detect.sh        # Rileva famiglia, installa dipendenze host
    |
    +-- DistroClone.sh          # Orchestratore principale (30 step)
            |
            +-- rsync /  -->  /mnt/distroClone-dest
            |
            +-- mksquashfs  -->  filesystem.squashfs
            |
            +-- xorriso     -->  distroClone-TIMESTAMP.iso
                    |
                    +-- [boot della ISO] --> Calamares
                                |
                                +-- calamares-config.sh     # Core YAML generator
                                |       +-- calamares-config-arch.sh
                                |       +-- calamares-config-fedora.sh
                                |
                                +-- dc-crypto.sh            # Orchestrator crypto
                                        +-- dc-grub.sh
                                        +-- dc-initramfs.sh
                                        +-- dc-grub.sh (rootflags)
```

Separazione delle responsabilità

| File | Contesto | Responsabilità | Righe |
|------|----------|----------------|-------|
| DistroClone.sh | HOST LIVE | Pipeline clone + ISO assembly | ~5.500 |
| distro-detect.sh | HOST LIVE | Detection + dipendenze | ~586 |
| calamares-config.sh | CHROOT CAL | Generazione YAML Calamares | ~2.330 |
| calamares-config-arch.sh | CHROOT CAL | Override famiglia Arch | ~646 |
| calamares-config-fedora.sh | CHROOT CAL | Override famiglia Fedora/openSUSE | ~1.842 |
| dc-crypto.sh | CHROOT CAL | LUKS detection + orchestrazione crypto | ~210 |
| dc-grub.sh | CHROOT CAL | GRUB install + BLS + btrfs rootflags | ~465 |
| dc-initramfs.sh | CHROOT CAL | initramfs multi-backend | ~130 |
| build-appimage.sh | BUILD | Assembly AppImage finale | ~472 |


03. Struttura dei file principali

DistroClone.sh — L'orchestratore

Il file più grande del progetto (circa 5.500 righe) coordina l'intera pipeline. Gestisce l'interfaccia utente (YAD/Zenity con fallback TTY), i messaggi multilingua (EN/IT/FR/ES/DE/PT) e i 30 step del processo di clonazione.

Un aspetto critico: contiene due heredoc CHROOT enormi (CHROOT_ARCH_EOF e CHROOT_FEDORA_EOF, oltre 1.000 righe ciascuno) che vengono eseguiti dentro il chroot Calamares durante l'installazione. Questo è il meccanismo con cui il codice host raggiunge il sistema installato.

```bash
# Esempio: heredoc CHROOT_ARCH_EOF (semplificato)
DC_CHROOT="$(cat << 'CHROOT_ARCH_EOF'
#!/bin/bash
# Questo codice gira DENTRO il chroot del sistema installato

# 1. Rimuove hook live da mkinitcpio
sed -i '/archiso/d' /etc/mkinitcpio.conf

# 2. Genera initramfs pulito
mkinitcpio -P

# 3. Installa dc-firstboot.service
...
CHROOT_ARCH_EOF
)"
```

distro-detect.sh — Il cervello del rilevamento

Implementa una cascata di detection a 4 livelli: file /etc/os-release (campo ID), campo ID_LIKE, file sentinella (/etc/arch-release ecc.), e infine package manager detection come ultimo fallback.

Caso speciale Garuda: Garuda usa dracut come initramfs sull'host, ma la ISO clonata deve usare mkinitcpio-archiso (come tutta la famiglia Arch). La detection distingue DC_INITRAMFS=dracut (tool host) da DC_LIVE_STACK=archiso (stack finale ISO) — sono variabili diverse con scopi distinti.

| Famiglia | Distro mappate | Package Manager | Live User |
|----------|---------------|-----------------|-----------|
| ARCH | arch, manjaro, endeavouros, garuda, arcolinux, artix, cachyos, biglinux | pacman | archie / cachyos |
| FEDORA | fedora, rhel, centos, almalinux, rocky, nobara, ultramarine, bazzite | dnf | liveuser |
| OPENSUSE | opensuse*, sles, sled, tumbleweed, leap | zypper | linux |
| DEBIAN | debian, ubuntu, mint, kali, popos, zorin, elementary, mx, antix | apt | admin |

calamares-config.sh — Il generatore YAML

Gira esclusivamente nel chroot Calamares durante l'installazione. Scrive dinamicamente tutti i file di configurazione Calamares (.conf YAML) basandosi sulla famiglia rilevata, sul filesystem scelto e sulle opzioni di cifratura.

Moduli Calamares generati a runtime:

```
unpackfs.conf         # Source squashfs + exclude patterns
mount.conf            # extraMounts: proc, sys, dev, run, efivarfs
fstab.conf            # Mount options per FS (btrfs: compress=zstd, ext4: discard)
users.conf            # doReusePassword, wheel sudoers, password requirements
partition.conf        # EFI 300M, btrfs nativo openSUSE, ext4 altrove
bootloader.conf       # GRUB/systemd-boot, EFI ID
services-systemd.conf # Disabilita servizi live (archiso*, cachyos*, pacman-init)
displaymanager.conf   # Rimuove autologin
shellprocess_*.conf   # Script custom pre/post install
```

Una delle parti più complesse è la gestione delle 3 sequenze di esecuzione Calamares, necessaria perché non tutte le distro hanno tutti i moduli C++ disponibili.

| Sequenza | Moduli C++ | Caso d'uso |
|----------|-----------|------------|
| FULL C++ | partition + mount + unpackfs | Fedora, openSUSE (kpmcore presente) |
| HYBRID | partition (UI) + mountbridge (Python) | Fallback se mount/unpackfs mancano |
| SHELLPROCESS | nessuno | Minimalista: disk-setup via YAD + tutto script |


04. La pipeline in 30 step

La pipeline è sequenziale e numerata. Ogni step stampa un messaggio localizzato e può fallire con exit 1 o procedere con warning non bloccante.

Step 01-07 — Host preparation: detect famiglia distro, installa dipendenze mancanti via package manager nativo, configura GRUB live, verifica spazio disco (minimo 8GB), seleziona tool GUI (YAD/Zenity/TTY), mostra dialogo di benvenuto con selezione compressione squashfs.

Step 08 — rsync clone: rsync -aAXH --one-file-system / verso /mnt/distroClone-dest con esclusioni critiche: /dev/*, /proc/*, /sys/*, /run/*, /tmp/*, /home/*, /snap, /.snapshots, cache zypper/apt, log. Il flag --one-file-system previene la copia di filesystem montati separatamente.

Step 09-15 — Cleanup e branding: rimozione utenti host da /home/* e /root/* (anche post-rsync), configurazione branding Calamares (logo, welcome, show.qml), copia /etc/skel, configurazione live user con password predefinita, mascheramento servizi live aggressivi.

Step 16-20 — Chroot build: rigenera initramfs (mkinitcpio / dracut), installa dc-firstboot.service, copia kernel + initramfs in /live/, verifica integrità /boot, gestisce layout BLS per Fedora/openSUSE.

Step 21 — Manual edit (opzionale): pausa interattiva che permette modifiche manuali al filesystem prima della compressione, utile per debug o personalizzazioni avanzate.

Step 22-23 — Squashfs: selezione compressione (lz4 circa 5 minuti, xz circa 20 minuti, xz-bcj circa 35 minuti), mksquashfs con -noappend -comp.

Step 24-28 — ISO assembly: generazione grub.cfg live, copia binari EFI, creazione efiboot.img (UEFI), isolinux (BIOS), xorriso per l'assemblaggio ISO finale con flag -isohybrid-mbr per supporto sia BIOS che UEFI.

Step 29-30 — Finalizzazione: verifica ISO (md5sum + sha256sum), rimozione Calamares e live-boot dall'host (cleanup post-build), output path e dimensione ISO.

Variabili globali chiave:

```bash
SOURCE="/"                           # Sorgente clone (sempre root host)
DEST="/mnt/distroClone-dest"        # Destinazione rsync
SQUASHFS_FILE="$DEST/filesystem.squashfs"
ISO_LABEL="DC_$(date +%Y%m%d)"      # Label ISO (usata in grub.cfg per search)
DC_BOOT_PARAMS="quiet loglevel=3 ..." # Parametri kernel live
DC_VERSION="1.3.6"                   # Versione AppImage
DC_ROOT_PASSWORD="distroClone1!"     # Password root live default
```


05. Gestione cross-distro delle famiglie

Il problema principale nel supporto cross-distro non è la clonazione del rootfs (rsync funziona ovunque) ma il bootloader, l'initramfs e i servizi live che sono profondamente family-specific. DistroClone risolve questo con un sistema di plugin-override a due livelli.

Il plugin pattern:

```bash
# calamares-config.sh: funzioni "abstract" che i plugin devono implementare
dc_set_paths()           # Popola CAL_MODULES, SQUASHFS_PATH, GRUB_CMD
dc_users_conf()          # Genera users.conf (sudoers, wheel group, password)
dc_remove_live_user()    # Script per rimozione utente live post-install
dc_configure_family()    # Config specifica: mkinitcpio, servizi, firstboot
dc_settings_conf()       # Sequenza exec moduli Calamares

# I plugin (calamares-config-arch.sh, calamares-config-fedora.sh)
# vengono sourciati e sovrascrivono queste funzioni
if [ "$DC_FAMILY" = "arch" ]; then
    source calamares-config-arch.sh
elif [ "$DC_FAMILY" = "fedora" ] || [ "$DC_FAMILY" = "opensuse" ]; then
    source calamares-config-fedora.sh
fi
```

Differenze critiche per famiglia:

| Aspetto | Arch family | Fedora family | openSUSE family |
|---------|------------|--------------|----------------|
| initramfs tool | mkinitcpio | dracut | dracut |
| GRUB command | grub-install | grub2-install | grub2-install |
| GRUB config | /boot/grub/grub.cfg | /boot/grub2/grub.cfg | /boot/grub2/grub.cfg |
| BLS entries | No | Si (/boot/loader/entries/) | Si |
| LUKS param | cryptdevice=UUID=... | rd.luks.uuid=... | rd.luks.uuid=... |
| btrfs layout | flat (@snapshots) | N/A | nested (@/.snapshots) |
| Snapper post-install | config preservata | N/A | config rimossa + ricreata da firstboot |
| Squashfs path | /run/archiso/bootmnt/arch/x86_64/airootfs.sfs | /run/initramfs/live/LiveOS/squashfs.img | variabile (4 path possibili) |

Il caso Garuda: doppio stack

Garuda è la distro più complessa da gestire perché usa dracut sull'host (invece di mkinitcpio come il resto della famiglia Arch) ma la ISO clonata deve usare archiso + mkinitcpio per compatibilità con il live boot stack.

```bash
# Detection Garuda in distro-detect.sh
case "$ID" in
    garuda)
        DC_FAMILY="arch"
        DC_INITRAMFS="dracut"    # Tool host (per diagnostica)
        DC_LIVE_STACK="archiso"  # Stack ISO finale (sempre archiso)
        ;;
esac

# Nel chroot CHROOT_ARCH_EOF, per Garuda:
# 1. Rimuovi dracut dalla live (potrebbe interferire)
# 2. Installa mkinitcpio-archiso hooks
# 3. Rigenera initramfs con mkinitcpio -P
```


06. Crypto layer: LUKS + btrfs

Il crypto layer è il componente più delicato dell'intero progetto. Gira esclusivamente nel chroot Calamares, il che significa che molti comandi normali non funzionano (findmnt mostra l'host, non il target). dc-crypto.sh implementa workaround specifici per questo contesto.

LUKS detection a cascata:

```bash
_dc_detect_crypto() {
    # Metodo 1: /dev/mapper/luks-* in /etc/fstab (Calamares standard)
    if grep -q '/dev/mapper/luks-' /etc/fstab; then
        LUKS_UUID=$(awk ... /etc/fstab)
        CRYPTO_TYPE="luks"; return
    fi

    # Metodo 2: /etc/crypttab (fstab usa UUID=)
    if [ -f /etc/crypttab ]; then
        LUKS_UUID=$(awk '$1~/^luks-/{print $2}' /etc/crypttab | sed 's/UUID=//')
        ...
    fi

    # Metodo 3: lsblk TYPE=crypt (solo su sistema live, non in chroot)
    LUKS_UUID=$(lsblk -rno TYPE,UUID | awk '$1=="crypt"{print $2}')
}
```

Parametri LUKS per famiglia

Un bug storico in DistroClone era l'uso di cryptdevice= (parametro mkinitcpio) anche per Fedora, che richiede rd.luks.uuid= (parametro dracut). Oggi i parametri sono distinti per backend initramfs:

```bash
# Arch (hook 'encrypt' di mkinitcpio)
GRUB_CMDLINE_LINUX="cryptdevice=UUID=$LUKS_UUID:$MAPPER root=/dev/mapper/$MAPPER"

# Fedora/openSUSE (modulo crypt di dracut)
GRUB_CMDLINE_LINUX="rd.luks.uuid=$LUKS_UUID root=/dev/mapper/$MAPPER"
```

btrfs: due layout, due strategie

Il filesystem btrfs è gestito in modo diverso tra Arch e openSUSE perché usano layout di subvolume incompatibili.

| Aspetto | Arch/CachyOS (flat) | openSUSE (nested) |
|---------|--------------------|--------------------|
| Root subvol | @ | @ |
| Snapshots path | @snapshots -> /.snapshots | @/.snapshots -> /.snapshots |
| Snapper config | Preservata (grub-btrfs legge natively) | Rimossa + ricreata da dc-firstboot |
| GRUB snapshot | grub-btrfs-snapper.service | grub2-snapper-plugin (menu vuoto, known limitation) |
| dc-firstboot | Crea /.snapshots se manca, abilita grub-btrfsd | snapper create-config + zypper install grub2-snapper-plugin |

```bash
# Rilevamento subvolume @ per rootflags injection
dc_configure_btrfs_rootflags() {
    _root_fs=$(awk '$2=="/" && $1!="none" {print $3}' /etc/fstab | head -1)
    [ "$_root_fs" != "btrfs" ] && return 0

    if ! btrfs subvolume list / 2>/dev/null | grep -qE 'path @$'; then
        return 0  # btrfs senza @, rootflags non necessario
    fi

    # Inietta rootflags=subvol=@ in tre punti:
    # 1. /etc/default/grub (GRUB_CMDLINE_LINUX)
    # 2. /etc/kernel/cmdline (BLS Fedora/openSUSE)
    # 3. /boot/loader/entries/*.conf (BLS entries, opzioni kernel)
}
```


07. Generazione dinamica della configurazione Calamares

Calamares è un installer Linux generico che legge la propria configurazione da file YAML. DistroClone non include questi file statici — li genera a runtime dentro il chroot in base alla famiglia rilevata, al filesystem scelto, alla presenza o meno di LUKS, e ai moduli C++ disponibili.

Emergency fstab repair

Su layout btrfs complessi, Calamares a volte genera un /etc/fstab incompleto (mancano i subvolumi secondari). DistroClone implementa un repair automatico post-installazione:

```bash
# Emergency fstab repair (calamares-config.sh)
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")

# Rileva subvolumi btrfs montati
btrfs subvolume list / | while read -r id gen parent top path; do
    # Mappa path --> mountpoint (@/home --> /home, @/var --> /var, ecc.)
    mountpoint=$(echo "$path" | sed 's|^@||; s|^$|/|')
    # Scrivi entry fstab con opzioni corrette
    echo "UUID=$ROOT_UUID $mountpoint btrfs subvol=$path,compress=zstd 0 0"
done >> /etc/fstab
```

Gestione servizi live

Ogni famiglia ha servizi live che devono essere disabilitati nel clone installato. Il caso più delicato è CachyOS, che ha un servizio (cachyos-configure-after-reboot.service) che sovrascrive /etc/shadow al primo boot, invalidando la password impostata da Calamares.

```yaml
# services-systemd.conf Arch/CachyOS
disable:
  - archiso-copy-passwd.service
  - archiso-reconfiguration.service
  - cachyos-configure-after-reboot.service   # CRITICO: sovrascrive shadow!
  - pacman-init.service
  - clean-live.service
```

Non basta il disable: il servizio viene mascherato con un symlink a /dev/null, altrimenti systemd lo riabilita al preset.

```bash
ln -sf /dev/null \
    /etc/systemd/system/cachyos-configure-after-reboot.service
```


08. GRUB layer: live ISO e clone installato

Il GRUB layer si articola in due contesti con comportamenti intenzionalmente diversi.

| Contesto | File | Tema | Strategia |
|----------|------|------|-----------|
| Live ISO boot | DistroClone.sh | Noir Obsidian (custom DC) | theme.txt generato, background gradient |
| Clone installato | dc-grub.sh | Tema originale distro | GRUB_THEME non toccato |

Tema live: Noir Obsidian

Il tema live usa tre font .pf2 generati a runtime con grub-mkfont: DejaVuSerif-Bold 32pt (serif) per il nome distro, DejaVuSans 15pt per le voci menu, DejaVuSans 12pt per i subtitle.

```
# theme.txt — Noir Obsidian (live ISO)
desktop-image: "background.png"    # gradient #050d22 -> #020509
desktop-color: "#030912"

+ label { text = "GRUB Boot Menu"; color = "#2a4070"; font = "DCSmall" }
+ label { text = "${DISTRO_NAME}"; color = "#ffffff"; font = "DCTitle" }
+ label { text = ". . .";          color = "#1a3060"; font = "DCSmall" }

+ boot_menu {
    item_color          = "#3a5280"   # voci non selezionate: blu muted
    selected_item_color = "#ffffff"   # selezionata: bianco puro
    item_height = 38; item_padding = 16
}

+ progress_bar {
    id = "__timeout__"
    height = 2; show_text = false   # ultra sottile, ghost
    fg_color = "#1a3aaa"; bg_color = "#060e28"
}
```

GRUB UEFI install: 3 fallback layer

L'installazione UEFI dentro il chroot Calamares è fragile perché findmnt non funziona. dc-grub.sh implementa tre metodi in cascata per trovare la partizione EFI:

```bash
_dc_grub_uefi() {
    # Layer 1: /etc/fstab — mount di /boot/efi
    if grep -q '/boot/efi' /etc/fstab; then
        mount /boot/efi 2>/dev/null; ...
    fi

    # Layer 2: lsblk — cerca PARTTYPE EFI o FSTYPE vfat su DISK
    EFI_DEV=$(lsblk -rno NAME,PARTTYPE,FSTYPE "/dev/$DISK" | \
        awk '$2=="c12a7328-..."{print $1}')

    # Layer 3: blkid globale — cerca PARTTYPE EFI su tutto il sistema
    EFI_DEV=$(blkid -o device | while read dev; do
        blkid -s PARTTYPE -o value "$dev" | grep -qi "c12a7328" && echo "$dev"
    done | head -1)
}
```


09. Workaround e bug fix critici

Ogni distribuzione presenta comportamenti edge-case che richiedono workaround specifici. Di seguito i fix più significativi implementati nel progetto.

CachyOS GDM: "Session never registered" dopo pacman -Syu + reboot

Root cause: GDM crea /tmp/.X11-unix con ownership gdm-greeter:gdm 1755 invece di root:root 1777. XWayland fallisce, gnome-shell riceve SIGABRT, GDM rifiuta la password.

Fix (defense-in-depth a 3 layer): (L1) /etc/tmpfiles.d/zz-dc-x11-unix.conf corregge l'ownership al boot via systemd-tmpfiles; (L2) dc-x11-unix-enforce.service applica un enforcement esplicito con After=tmpfiles-setup e Before=display-manager; (L3) dc-firstboot.service costituisce il safety net al primo boot.

Arch: LUKS kernel param sbagliato (cryptdevice= vs rd.luks.uuid=)

Root cause: il parametro cryptdevice= è specifico dell'hook encrypt di mkinitcpio. Fedora e openSUSE usano dracut, che richiede rd.luks.uuid=. Il bug causava kernel panic al boot su sistemi cifrati Fedora.

Fix: dc-grub.sh seleziona il parametro in base a DC_DISTRO (arch usa cryptdevice, fedora e opensuse usano rd.luks.uuid).

Fedora: GRUB menu vuoto con GRUB_ENABLE_BLSCFG=false

Root cause: disabilitare BLS su Fedora produce un menu GRUB con sola voce "UEFI Firmware Settings" perché grub2-mkconfig di Fedora delega la generazione delle voci kernel al BLS parser. Senza BLS entries in /boot/loader/entries/, il menu è vuoto.

Fix: non disabilitare GRUB_ENABLE_BLSCFG. Se le BLS entries mancano, dc-grub.sh le ricrea con kernel-install add o con un writer manuale in bash.

openSUSE: fstab subvolume detection rotto da subshell-pipe

Root cause: btrfs subvolume list / | while read crea una subshell; le variabili assegnate dentro non sono visibili fuori. Il fstab risultante era vuoto.

Fix: sostituito con var=$(cmd) seguito da for key in $known_keys — nessuna pipe, nessuna subshell.

AppImage: script stale nel squashfs (tee buffering)

Root cause: calamares-config.sh generato inline via tee in un AppImage usava buffering — l'AppImage leggeva la versione precedente ancora in cache FUSE.

Fix: AppRun copia tutto in /tmp/distroClone-run-XXXX prima di eseguire, garantendo lettura dal filesystem reale.

openSUSE: dracut hang in chroot durante initramfs

Root cause: dracut senza --hostonly in chroot scansiona tutto l'hardware reale e si blocca su device non accessibili dal chroot.

Fix: --hostonly in chroot Calamares. Il sistema installato ha LUKS attivo, quindi hostonly è corretto ed è circa 10 volte più veloce.


10. Build dell'AppImage

build-appimage.sh assembla il tutto in un singolo eseguibile AppImage type2. La struttura è un squashfs preceduto dal runtime stub FUSE che monta il filesystem senza installazione.

```
# Struttura AppDir
AppDir/
  AppRun                              # Entry point: preserva env display, copia in /tmp
  usr/share/distroClone/
    DistroClone.sh
    distro-detect.sh
    calamares-config.sh
    calamares-config-arch.sh
    calamares-config-fedora.sh
    dc-crypto.sh
    dc-initramfs.sh
    dc-grub.sh
  usr/share/applications/distroClone.desktop
  usr/share/icons/hicolor/{48x48,128x128,256x256}/apps/distroClone.png

# Assembly finale
mksquashfs AppDir AppDir.squashfs \
    -comp zstd -Xcompression-level 19 \
    -root-owned -noappend

cat runtime-x86_64 AppDir.squashfs > distroClone-1.3.6-x86_64.AppImage
chmod +x distroClone-1.3.6-x86_64.AppImage
```

Il ciclo di vita AppRun:

1. Verifica root ($EUID == 0); se no, rilancia con sudo preservando DISPLAY, WAYLAND_DISPLAY, DBUS_SESSION_BUS_ADDRESS, XAUTHORITY.

2. Copia critica in /tmp prima di qualsiasi operazione. Il mount FUSE dell'AppImage è instabile se un processo figlio tenta di accedere agli stessi file mentre il parent li sta leggendo.

3. Source distro-detect.sh -> dc_bootstrap(): rileva famiglia, verifica dipendenze, installa i pacchetti mancanti con il package manager nativo.

4. Gestisce argomenti speciali: --version (stampa versione ed esce), --detect (mostra info distro ed esce), --install-deps (solo installazione dipendenze).

5. Avvia DistroClone.sh da /tmp/distroClone-run-XXXX, senza dipendenze dal mount FUSE.

Utilizzo:

```bash
# Rendi eseguibile
chmod +x distroClone-1.3.6-x86_64.AppImage

# Verifica distro rilevata
sudo ./distroClone-1.3.6-x86_64.AppImage --detect

# Installa solo dipendenze
sudo ./distroClone-1.3.6-x86_64.AppImage --install-deps

# Avvia pipeline completa
sudo ./distroClone-1.3.6-x86_64.AppImage

# Con lingua specifica
sudo ./distroClone-1.3.6-x86_64.AppImage --lang=it

# Rebuild AppImage dopo modifiche agli script
bash build-appimage.sh
```

Attenzione: qualsiasi modifica a calamares-config.sh, dc-crypto.sh, dc-initramfs.sh o dc-grub.sh richiede l'esecuzione di bash build-appimage.sh prima del test. L'AppImage è uno snapshot immutabile — modificare i file sorgente non aggiorna l'eseguibile.

Matrice funzionalità:

| Feature | Arch | CachyOS | Garuda | Fedora | openSUSE |
|---------|------|---------|--------|--------|----------|
| Clone + ISO | si | si | si | si | si |
| LUKS encryption | si | si | si | si | si |
| btrfs + subvolumi | si | si | si | no | si |
| Snapper + GRUB snapshots | si | si | no | no | parziale (menu vuoto) |
| BLS (Boot Loader Spec) | no | no | no | si | si |
| UEFI + BIOS | si | si | si | si | si |
| GUI YAD/Zenity | si | si | si | si | si |
| Compressione selezionabile | si | si | si | si | si |


distroClone-cross-distro v1.3.6 — post tecnico generato 2026-04-21
