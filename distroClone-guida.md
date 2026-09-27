# DistroClone Cross-Distro — Guida all'Uso

Clona il tuo sistema Linux in una ISO installabile — qualunque distribuzione tu stia usando.

**v1.3.7 · AppImage · Arch · Fedora · openSUSE · LUKS · btrfs · UEFI/BIOS · 6 lingue**

---

## Indice

1. [Cos'è DistroClone](#cosè-distroclone)
2. [Requisiti](#requisiti)
3. [Primo avvio](#primo-avvio)
4. [Schermata di benvenuto](#schermata-di-benvenuto)
5. [Opzioni di compressione](#opzioni-di-compressione)
6. [Configurazioni utente](#configurazioni-utente)
7. [Configurazioni avanzate](#configurazioni-avanzate)
8. [La pipeline in 30 step](#la-pipeline-in-30-step)
9. [Build Log](#build-log)
10. [Completamento e test della ISO](#completamento-e-test-della-iso)
11. [Argomenti da riga di comando](#argomenti-da-riga-di-comando)
12. [Distribuzioni supportate](#distribuzioni-supportate)

---

## Cos'è DistroClone

DistroClone è uno strumento Bash distribuito come **AppImage autocontenuto** che esegue un'istantanea completa del tuo sistema Linux live e la impacchetta in una **ISO avviabile con installer Calamares**. Avvia la ISO su qualsiasi macchina compatibile e ottieni un'installazione identica all'originale: pacchetti, configurazione, layout di filesystem, cifratura LUKS e subvolumi btrfs inclusi.

A differenza degli strumenti mono-famiglia (Remastersys, Refracta, penguins-eggs), DistroClone Cross-Distro supporta nativamente le famiglie **Arch**, **Fedora** e **openSUSE** con un'architettura plugin-based che separa la pipeline invariante dagli override specifici per famiglia.

> **Nessuna installazione richiesta.** Scarica l'AppImage, rendila eseguibile e avviala come root. Le dipendenze vengono installate automaticamente tramite il package manager nativo.

---

## Requisiti

| Requisito | Dettaglio |
|-----------|-----------|
| Architettura | x86_64 |
| Spazio disco libero | Minimo 8 GB (consigliato ≥ 20 GB per sistemi grandi) |
| RAM | 4 GB minimo |
| Sistema operativo | Linux live o installato — famiglia Arch, Fedora o openSUSE |
| Interfaccia grafica | Opzionale — fallback automatico su TTY se YAD/Zenity non sono presenti |
| Privilegi | Root (`sudo` o direttamente come root) |

> **Attenzione:** DistroClone clona il sistema *live in esecuzione*. Deve girare sullo stesso sistema che si vuole clonare, non da un sistema esterno.

---

## Primo avvio

```bash
# 1. Rendi l'AppImage eseguibile
chmod +x distroClone-1.3.7-x86_64.AppImage

# 2. (Opzionale) Verifica quale famiglia di distro viene rilevata
sudo ./distroClone-1.3.7-x86_64.AppImage --detect

# 3. (Opzionale) Installa solo le dipendenze senza avviare il clone
sudo ./distroClone-1.3.7-x86_64.AppImage --install-deps

# 4. Avvia la pipeline completa
sudo ./distroClone-1.3.7-x86_64.AppImage
```

All'avvio, DistroClone rileva automaticamente la distribuzione host, installa le dipendenze mancanti (xorriso, squashfs-tools, calamares, ecc.) e apre l'interfaccia grafica. Se un display X/Wayland non è disponibile, passa automaticamente a una modalità testuale (TTY).

---

## Schermata di benvenuto

La prima schermata mostra un riepilogo del sistema rilevato e le opzioni principali da configurare prima di avviare il clone.

![Schermata di benvenuto DistroClone](1.png)
*Schermata di benvenuto: sistema rilevato (Garuda Linux, kernel 6.13.x), ISO da creare, tipo di compressione squashfs e filesystem preferito.*

La schermata mostra tre sezioni principali:

### System Detected

Distribuzione, versione del kernel e utente live rilevati automaticamente. Non richiede configurazione manuale.

### ISO Created

Il percorso e il nome della ISO che verrà generata, con timestamp automatico nel formato `distroClone-YYYYMMDD-HHMMSS.iso`.

### Opzioni principali

**Squashfs compression type** — Seleziona l'algoritmo di compressione per il filesystem squashfs. Vedi la sezione dedicata per i dettagli su ogni opzione.

**Preferred live filesystem** — Il filesystem del sistema clonato: `ext4`, `btrfs` o `xfs`. Calamares userà questo come default nell'installer.

---

## Opzioni di compressione

La compressione del filesystem squashfs determina la dimensione della ISO finale e il tempo necessario alla creazione. Scegli in base al bilanciamento velocità / dimensione che preferisci.

![Selezione compressione squashfs](2.png)
*Le opzioni di compressione disponibili: Standard (lz4), Fast (xz) e Maximum (xz-bcj).*

| Opzione | Algoritmo | Tempo stimato | Dimensione ISO | Quando usarla |
|---------|-----------|---------------|----------------|---------------|
| **Standard** | `lz4` | ~5 min | Maggiore | Test rapidi, debug, iterazioni frequenti |
| **Fast** | `xz` | ~20-25 min | Ridotta | Distribuzione generale, buon equilibrio |
| **Maximum** | `xz -bcj` | ~30-35 min | Minima | ISO per distribuzione pubblica, pendrive |

> **Consiglio:** durante le prime prove usa **Standard (lz4)** per validare che il processo funzioni correttamente. Passa a **Maximum** solo per la ISO definitiva da distribuire.

---

## Configurazioni utente

Durante la pipeline, DistroClone chiede se copiare le configurazioni dell'utente corrente nella ISO. Questa è una scelta con implicazioni importanti sulla privacy e sull'esperienza dell'utente finale.

![Dialogo configurazioni utente](4.png)
*Il dialogo spiega con precisione cosa viene incluso e cosa viene escluso quando si scelgono di copiare le configurazioni utente.*

### Se scegli Yes (Sì)

Il nuovo utente creato da Calamares al momento dell'installazione troverà:

- Stesse impostazioni (tema, icone, desktop, layout)
- Stessa configurazione di pannelli e barre
- Stessi sfondi e preferenze visive

### Cosa *non* viene mai copiato

- Password e credenziali
- Documenti e file personali
- Configurazioni VirtualBox / macchine virtuali

> **Raccomandato per distribuzioni personalizzate.** Se vuoi creare una ISO da distribuire ad altri con il tuo setup visivo già configurato, scegli **Yes**. Se vuoi una ISO pulita con configurazione predefinita, scegli **No**.

---

## Configurazioni avanzate

Prima della compressione squashfs, DistroClone offre un **punto di pausa interattivo** che permette modifiche manuali al filesystem clonato. Questa funzione è pensata per utenti avanzati.

![Dialogo configurazioni avanzate](5.png)
*Il dialogo di configurazione avanzata: sospende la pipeline per permettere modifiche manuali al filesystem prima della compressione.*

### Cosa puoi fare durante il manual edit

- Entrare nel chroot del sistema clonato (`arch-chroot /mnt/distroClone-dest`)
- Rimuovere pacchetti indesiderati prima della compressione
- Aggiungere file di configurazione personalizzati
- Modificare file di testo nel filesystem clonato
- Installare pacchetti aggiuntivi che verranno inclusi nella ISO

> **Attenzione:** questa opzione è per utenti esperti. Modifiche errate al filesystem possono produrre una ISO non avviabile. Per un clone standard, scegli **No, continue**.

Quando scegli **Yes, I want to edit**, la pipeline si sospende e il terminale è libero. Digita `exit` e premi Invio per riprendere la pipeline dalla fase di compressione.

---

## La pipeline in 30 step

DistroClone esegue il processo di clonazione in 30 step numerati e sequenziali. Ogni step stampa un messaggio localizzato e può completarsi con successo, avanzare con un avviso non bloccante, o fermarsi con errore critico.

| Step | Fase | Descrizione |
|------|------|-------------|
| 01-07 | Preparazione host | Rilevamento distribuzione, installazione dipendenze mancanti, verifica spazio disco (min 8 GB), selezione tool GUI |
| 08 | Clone rsync | Copia dell'intero filesystem root verso `/mnt/distroClone-dest` con esclusione di `/dev`, `/proc`, `/sys`, `/tmp`, `/home`, cache e log |
| 09-15 | Cleanup e branding | Rimozione utenti host, configurazione logo e branding Calamares, copia `/etc/skel`, mascheramento servizi live |
| 16-20 | Build chroot | Rigenerazione initramfs (mkinitcpio o dracut), installazione `dc-firstboot.service`, copia kernel e initramfs in `/live/` |
| 21 | Manual edit | Pausa interattiva opzionale per modifiche manuali prima della compressione |
| 22-23 | Compressione squashfs | Creazione del filesystem squashfs con l'algoritmo selezionato |
| 24-28 | Assemblaggio ISO | Generazione GRUB live, binari EFI, immagine `efiboot.img`, isolinux BIOS, assemblaggio con `xorriso` con supporto ibrido BIOS/UEFI |
| 29-30 | Finalizzazione | Verifica integrità ISO (MD5 + SHA256), cleanup file temporanei, output percorso e dimensione file finale |

---

## Build Log

Durante l'esecuzione, una finestra di **Build Log** mostra in tempo reale lo stato di ogni step. Il log è utile per diagnosticare problemi o semplicemente seguire l'avanzamento.

![Finestra Build Log con step in esecuzione](3.png)
*La finestra Build Log mostra i 30 step in esecuzione in tempo reale, con messaggi di stato per ogni fase del processo.*

![Terminale durante la build](6.png)
*Il terminale durante la fase di build: pacchetti elaborati, montaggio filesystem, generazione GRUB e avanzamento dei vari step.*

Se un passaggio fallisce, il log mostra il messaggio di errore specifico. Gli errori critici interrompono la pipeline; gli avvisi non bloccanti vengono registrati ma il processo continua.

---

## Completamento e test della ISO

Al termine del processo, DistroClone mostra una finestra di riepilogo con il percorso della ISO generata, le istruzioni per testarla in una VM e i checksum di integrità.

![Schermata completamento ISO](7.png)
*La schermata finale conferma il successo e fornisce il percorso della ISO e i comandi per testarla con GNOME Boxes o VirtualBox.*

![Terminale con checksum ISO](8.png)
*Output finale nel terminale: percorso ISO, dimensione file, checksum MD5 e SHA256 per verifica integrità.*

### Testare la ISO con GNOME Boxes

```bash
gnome-boxes ~/garuda_live/distroClone-live-rolling.iso
```

### Flashare la ISO su USB

```bash
# Sostituisci /dev/sdX con il tuo dispositivo USB
dd if=/percorso/distroClone-live-rolling.iso \
   of=/dev/sdX bs=4M status=progress oflag=sync
```

> **La ISO è ibrida BIOS/UEFI.** Funziona sia su hardware con UEFI Secure Boot disabilitato sia su hardware legacy BIOS senza configurazione aggiuntiva.

---

## Argomenti da riga di comando

L'AppImage accetta argomenti speciali per operazioni di diagnostica o configurazione senza avviare la pipeline completa.

| Argomento | Effetto |
|-----------|---------|
| `--detect` | Mostra la famiglia di distro rilevata, variabili DC_ e informazioni sul sistema. Esce senza clonare. |
| `--install-deps` | Installa solo le dipendenze necessarie tramite il package manager nativo. |
| `--version` | Stampa la versione dell'AppImage ed esce. |
| `--lang=XX` | Forza la lingua dell'interfaccia. Valori: `it`, `en`, `fr`, `es`, `de`, `pt`. |

```bash
# Diagnostica: vedi cosa rileva senza fare nulla
sudo ./distroClone-1.3.7-x86_64.AppImage --detect

# Interfaccia in italiano
sudo ./distroClone-1.3.7-x86_64.AppImage --lang=it

# Solo installazione dipendenze (nessun clone)
sudo ./distroClone-1.3.7-x86_64.AppImage --install-deps
```

---

## Distribuzioni supportate

DistroClone Cross-Distro supporta tre famiglie di distribuzioni. Per la famiglia Debian/Ubuntu esiste un branch separato con pacchetto `.deb`.

| Distribuzione | Famiglia | Clone ISO | LUKS | btrfs | Snapper | BLS | UEFI/BIOS |
|---------------|----------|-----------|------|-------|---------|-----|-----------|
| Arch Linux | arch | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| CachyOS | arch | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| EndeavourOS | arch | ✓ | ✓ | ✓ | — | — | ✓ |
| Garuda Linux | arch | ✓ | ✓ | ✓ | — | — | ✓ |
| Manjaro | arch | ✓ | ✓ | ✓ | — | — | ✓ |
| Fedora | fedora | ✓ | ✓ | — | — | ✓ | ✓ |
| openSUSE Tumbleweed | opensuse | ✓ | ✓ | ✓ | parz. | ✓ | ✓ |

**Famiglia Debian/Ubuntu:** usa il branch separato su [github.com/fconidi/distroClone](https://github.com/fconidi/distroClone) con pacchetto `.deb` dedicato.

---

*DistroClone Cross-Distro — sviluppato da Franco Conidi · [francoconidi.it](https://francoconidi.it)*
