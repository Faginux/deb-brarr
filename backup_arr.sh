#!/usr/bin/env bash
# ====================================================================================
# backup_arr.sh - Script di backup e rollback BTRFS completo
# Creato da Oscar & ChatGPT (OpenAI)
# Effettua backup di Radarr, Sonarr, Plex, Notifiarr, qBittorrent, NoMachine e altre configurazioni
# con verifica integrità, compressione, archiviazione e rollback snapshot
# ====================================================================================

set -euo pipefail  # Abilita uscita su errori, variabili non definite, errori in pipeline

# === CONFIGURAZIONI ===
BASE_DEVICE="/dev/mapper/VGO-LGO"    # Dispositivo LVM con filesystem BTRFS
BTRFS_MNT="/mnt/btrfs"               # Punto di mount temporaneo per BTRFS
USB_MNT="/mnt/usb"                   # Punto di mount per chiavetta USB
BACKUP_BASE="/backups"               # Directory di backup incrementale
LOGFILE="/var/log/backup_arr.log"    # Log file principale
LOGROTATE_CONF="/etc/logrotate.d/backup_arr"  # Config logrotate
INCREMENTAL=true                      # Abilita backup incrementali
ROLLBACK=true                         # Abilita rollback snapshot
dry=false                             # Modalità DRY-RUN se true
RESTORE_ONLY=false                    # Se true, salta il backup ed esegue solo restore

# === SCELTA INTERATTIVA DEI MODULI DA BACKUP ===
echo "Seleziona quali moduli vuoi includere nel backup (separa con spazi):"
echo "1) servarr  2) users  3) nx  4) misc  5) tutti"
read -rp "Inserisci numeri (es: 1 3 4): " choices
BACKUP_ONLY=""
for choice in $choices; do
  case $choice in
    1) BACKUP_ONLY+="servarr " ;;  # Aggiunge Servarr
    2) BACKUP_ONLY+="users " ;;    # Aggiunge utenti
    3) BACKUP_ONLY+="nx " ;;       # Aggiunge NoMachine server
    4) BACKUP_ONLY+="misc " ;;     # Aggiunge file di sistema
    5) BACKUP_ONLY="all"; break ;; # Seleziona tutti i moduli
    *) echo "[WARN] Scelta non valida: $choice" ;;
  esac
done

# === FUNZIONI DI UTILITÀ ===
require_cmd() { command -v "$1" &>/dev/null || { echo "[ERROR] Missing: $1" >&2; exit 1; } }
# Controlla la presenza dei comandi richiesti
for cmd in lsblk vgchange btrfs mktemp rsync tar sha256sum zstd awk getopts logrotate xargs; do require_cmd "$cmd"; done

do_it() {  # Wrapper per eseguire un comando, oppure stampare se DRY-RUN
  if [[ "$dry" == true ]]; then echo "DRY-RUN: $*"; else eval "$*"; fi
  local status=$?
  if [[ $status -ne 0 ]]; then echo "[ERROR] Command failed: $*" >&2; exit $status; fi
}

# === FUNZIONI DI BACKUP CON COMMENTI DETTAGLIATI ===
backup_and_verify() {
  # Esegue il backup della directory sorgente $src nella destinazione $dst in due passaggi:
  # 1. Copia con rsync senza --delete
  # 2. Seconda rsync solo con --delete per pulizia file obsoleti
  # Poi verifica l'integrità dei file copiati calcolando hash SHA256 in parallelo

  local src="$1" dst="$2" linkdest=""
  mkdir -p "$dst"  # Crea la directory di destinazione se non esiste

  if [[ "$INCREMENTAL" == true && -d "$BACKUP_BASE/last$dst" ]]; then
    linkdest="--link-dest=$BACKUP_BASE/last$dst"  # Se è backup incrementale, usa link verso ultimo backup
  fi

  echo "-> Copia iniziale da $src a $dst (senza --delete)"
  do_it rsync -a -P --info=progress2 --no-inc-recursive $linkdest "$src/" "$dst/"  # Primo rsync solo copia

  echo "-> Pulizia file obsoleti in $dst (con --delete)"
  do_it rsync -a --delete --dry-run $linkdest "$src/" "$dst/"  # Secondo rsync simulato per mostrare cosa verrebbe cancellato
  read -rp "Procedere con cancellazione file non più presenti? [y/N]: " confirm_delete
  if [[ "$confirm_delete" =~ ^[yY]$ ]]; then
    do_it rsync -a --delete $linkdest "$src/" "$dst/"  # Secondo rsync eseguito davvero solo se confermato
  else
    echo "Cancellazione file obsoleti saltata."
  fi

  echo "-> Verifica SHA256 parallela..."
  export SRC_BASE="$src" DST_BASE="$dst"  # Esporta variabili per uso interno in xargs
  find "$src" -type f -print0 | xargs -0 -n1 -P"$(nproc)" bash -c '
    src_file="$1"  # File sorgente corrente
    rel="${src_file#$SRC_BASE}"  # Calcola percorso relativo rispetto a SRC_BASE
    dest_file="$DST_BASE$rel"  # Costruisce percorso di destinazione corrispondente
    [[ -f "$dest_file" ]] || { echo "[ERROR] Missing: $dest_file"; exit 1; }  # Controlla che file di destinazione esista
    src_hash=$(sha256sum "$src_file" | cut -d" " -f1)  # Calcola hash SHA256 del file sorgente
    dst_hash=$(sha256sum "$dest_file" | cut -d" " -f1)  # Calcola hash SHA256 del file destinazione
    [[ "$src_hash" == "$dst_hash" ]] || { echo "[ERROR] Checksum mismatch: $src_file"; exit 1; }  # Verifica che gli hash coincidano
  ' _
}

backup_servarr() {
  echo "== Backup Servarr apps =="
  for svc in radarr sonarr plexmediaserver notifiarr; do
    local src="$BTRFS_MNT/var/lib/$svc"
    local dst="$BACKUP_TMP/servarr_$svc"
    if [[ -d "$src" ]]; then
      backup_and_verify "$src" "$dst"
    else
      echo "[WARN] Directory non trovata: $src"
    fi
  done
}

backup_users() {
  echo "== Backup Utenti qBittorrent & NoMachine =="
  for homedir in /home/*; do
    [[ -d "$homedir" ]] || continue
    user=$(basename "$homedir")
    [[ -d "$homedir/.config/qBittorrent" ]] && backup_and_verify "$homedir/.config/qBittorrent" "$BACKUP_TMP/qbt_${user}_config"
    [[ -d "$homedir/.local/share/qBittorrent" ]] && backup_and_verify "$homedir/.local/share/qBittorrent" "$BACKUP_TMP/qbt_${user}_data"
    [[ -d "$homedir/.nx/config" ]] && backup_and_verify "$homedir/.nx/config" "$BACKUP_TMP/nx_${user}_client"
    [[ -d "$homedir/Documents/NoMachine" ]] && backup_and_verify "$homedir/Documents/NoMachine" "$BACKUP_TMP/nx_${user}_sessions"
  done
}

backup_nx_server() {
  echo "== Backup NoMachine server =="
  [[ -d "/usr/NX/etc" ]] && backup_and_verify "/usr/NX/etc" "$BACKUP_TMP/nx_server_etc"
  [[ -d "/etc/NX" ]] && backup_and_verify "/etc/NX" "$BACKUP_TMP/nx_etc"
}

backup_misc() {
  echo "== Backup config system =="
  [[ -f "$BTRFS_MNT/etc/fstab" ]] && do_it cp "$BTRFS_MNT/etc/fstab" "$BACKUP_TMP/fstab.btrfs"
  [[ -f "$LOGFILE" ]] && do_it cp "$LOGFILE" "$BACKUP_TMP/"
}


# === PREPARA MOUNT ===
# Crea una directory temporanea per i file di backup
BACKUP_TMP=$(mktemp -d)
# Crea i punti di mount per la chiavetta USB e il filesystem BTRFS se non esistono
mkdir -p "$USB_MNT" "$BTRFS_MNT"
# Mostra i dispositivi a blocchi disponibili (solo dischi e NVMe)
echo "Dispositivi disponibili:"; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'sd|nvme'
# Chiede all'utente quale dispositivo USB usare per montare la destinazione del backup
read -rp "Device USB (es: sdb1): " d; USB_DEV="/dev/${d##*/}"
# Verifica che il dispositivo esista come file a blocchi
[[ -b "$USB_DEV" ]] || { echo "[ERROR] Invalid device"; exit 1; }
# Monta il dispositivo USB sulla directory $USB_MNT
#do_it esegue il comando con controllo errori e supporto dry-run
do_it mount "$USB_DEV" "$USB_MNT"
# Attiva i volumi logici LVM se presenti (necessario per accedere a /dev/mapper/VGO-LGO)
do_it vgchange -ay
# Monta il volume BTRFS principale sul punto $BTRFS_MNT con subvolume @
do_it mount -o subvol=@ "$BASE_DEVICE" "$BTRFS_MNT"

# === ESEGUE I BACKUP SELEZIONATI ===
# Solo se RESTORE_ONLY è false esegue le funzioni di backup selezionate
[[ "$RESTORE_ONLY" == false ]] && {
  # Esegue backup_servarr se selezionato o se selezionato "all"
  [[ "$BACKUP_ONLY" == *all* || "$BACKUP_ONLY" == *servarr* ]] && backup_servarr
  # Esegue backup_users se selezionato o se selezionato "all"
  [[ "$BACKUP_ONLY" == *all* || "$BACKUP_ONLY" == *users* ]] && backup_users
  # Esegue backup_nx_server se selezionato o se selezionato "all"
  [[ "$BACKUP_ONLY" == *all* || "$BACKUP_ONLY" == *nx* ]] && backup_nx_server
  # Esegue backup_misc se selezionato o se selezionato "all"
  [[ "$BACKUP_ONLY" == *all* || "$BACKUP_ONLY" == *misc* ]] && backup_misc
}

# === ARCHIVIAZIONE ===
package_archive() {
  # Crea un file tar con timestamp e nome backup_arr_<timestamp>.tar
  local ts=$(date +'%Y%m%d_%H%M') arch="backup_arr_$ts.tar"
  # Crea archivio tar dei dati raccolti in $BACKUP_TMP
  do_it tar -cpf "$BACKUP_TMP/$arch" -C "$BACKUP_TMP" .
  # Calcola checksum SHA256 del file tar e salva in file .sha256
  do_it sha256sum "$BACKUP_TMP/$arch" > "$BACKUP_TMP/$arch.sha256"
  # Comprimi il file tar usando zstd livello 19
  do_it zstd -19 -f "$BACKUP_TMP/$arch"
  # Sposta l'archivio compresso e il file di checksum sulla chiavetta USB
  do_it mv "$BACKUP_TMP/$arch.zst" "$USB_MNT/"
  do_it mv "$BACKUP_TMP/$arch.sha256" "$USB_MNT/"
  echo "Archivio creato e spostato su USB"
  # Aggiorna il collegamento simbolico a ultimo backup se incrementale
  if [[ "$INCREMENTAL" == true ]]; then do_it rm -f "$BACKUP_BASE/last"; do_it ln -s "$USB_MNT/$arch.zst" "$BACKUP_BASE/last"; fi
}
package_archive

# === ROLLBACK SNAPSHOT INTERATTIVO ===
if [[ "$ROLLBACK" == true ]]; then
  # Chiede conferma all'utente prima di eseguire rollback
  read -rp "Vuoi procedere con il rollback di una snapshot? [y/N]: " confirm
  if [[ "$confirm" =~ ^[yY]$ ]]; then
    echo "=== Rollback snapshot ==="
    # Smonta il volume BTRFS per sicurezza prima di operare
    do_it umount "$BTRFS_MNT"
    # Rimonta il volume BTRFS senza specificare subvolume per accedere a @snapshots
    do_it mount "$BASE_DEVICE" "$BTRFS_MNT"
    # Lista gli snapshot disponibili con ID e percorso
    btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk '{print "ID:"$2,"Path:"$NF}'
    # Chiede all'utente l'ID della snapshot da ripristinare
    read -rp "ID snapshot: " sid
    # Recupera il percorso relativo della snapshot selezionata
    path=$(btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk -v i="$sid" '$2==i{print $NF}')
    # Elimina il subvolume @ corrente per liberare il mountpoint
    do_it btrfs subvolume delete "$BTRFS_MNT/@"
    # Crea una nuova snapshot da quella selezionata al posto di @
    do_it btrfs subvolume snapshot "$BTRFS_MNT/@snapshots/$path" "$BTRFS_MNT/@"
    echo "Snapshot $sid ripristinato. Riavvia il sistema."
  else
    echo "Rollback annullato."
  fi
fi

echo "Script completato con successo."
