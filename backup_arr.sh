#!/usr/bin/env bash
VERSION="1.2"

# ====================================================================================
# backup_arr.sh - Script di backup e rollback BTRFS completo con commenti didattici
# Creato da Oscar & ChatGPT (OpenAI)
# ====================================================================================

set -euo pipefail  # Ferma lo script su errori, variabili non definite, errori in pipe

# === CONFIGURAZIONI ===
BASE_DEVICE="/dev/mapper/VGO-LGO"   # Dispositivo principale (volume LVM)
BTRFS_MNT="/mnt/btrfs"               # Mountpoint temporaneo per BTRFS
USB_MNT="/mnt/usb"                   # Mountpoint per la USB di backup
BACKUP_BASE="/backups"               # Directory per backup incrementale
LOGFILE="/var/log/backup_arr.log"    # File di log
INCREMENTAL=true                      # Abilita backup incrementale
ROLLBACK=true                         # Permette esecuzione rollback a fine backup
dry=false                             # Modalità dry-run
RESTORE_ONLY=false                    # Modalità solo ripristino (non usata ora)

# === AUTO-ELEVAZIONE PRIVILEGI ===
if [ "$EUID" -ne 0 ]; then
  echo "[INFO] Riavvio lo script con sudo..."
  exec sudo "$0" "$@"
fi

# === CONTROLLO MOUNT GIA' ESISTENTI ===
if mountpoint -q "$USB_MNT"; then
  echo "[INFO] $USB_MNT è già montato."
  read -p "Vuoi smontare e rimontare $USB_MNT? [y/N]: " risposta
  if [[ "$risposta" =~ ^[yY]$ ]]; then umount "$USB_MNT"; fi
fi

if mountpoint -q "$BTRFS_MNT"; then
  echo "[INFO] $BTRFS_MNT è già montato."
  read -p "Vuoi smontare e rimontare $BTRFS_MNT? [y/N]: " risposta
  if [[ "$risposta" =~ ^[yY]$ ]]; then umount "$BTRFS_MNT"; fi
fi

# === MENU INTERATTIVO SELEZIONE MODULI BACKUP ===
echo "Seleziona cosa vuoi eseguire:"
echo "1) Backup completo (all)"
echo "2) Solo Servarr"
echo "3) Solo Users"
echo "4) Solo NoMachine"
echo "5) Solo Misc"
echo "6) Solo rollback snapshot"
read -rp "Inserisci numero: " scelta
case "$scelta" in
  1) BACKUP_ONLY="all" ;;
  2) BACKUP_ONLY="servarr" ;;
  3) BACKUP_ONLY="users" ;;
  4) BACKUP_ONLY="nx" ;;
  5) BACKUP_ONLY="misc" ;;
  6) BACKUP_ONLY="rollback" ;;
  *) echo "Scelta non valida."; exit 1 ;;
esac

# === CONTROLLO COMANDI ESSENZIALI ===
require_cmd() { command -v "$1" &>/dev/null || { echo "[ERROR] Missing: $1" >&2; exit 1; } }
for cmd in lsblk vgchange btrfs mktemp rsync tar sha256sum zstd awk getopts logrotate xargs; do require_cmd "$cmd"; done

# === FUNZIONE DI ESECUZIONE SICURA ===
do_it() {
  if [[ "$dry" == true ]]; then echo "DRY-RUN: $*"; else eval "$*"; fi
  local status=$?
  if [[ $status -ne 0 ]]; then echo "[ERROR] Command failed: $*" >&2; exit $status; fi
}

# === FUNZIONE BACKUP E VERIFICA INTEGRITÀ ===
backup_and_verify() {
  local src="$1" dst="$2" linkdest=""
  mkdir -p "$dst"
  if [[ "$INCREMENTAL" == true && -d "$BACKUP_BASE/last$dst" ]]; then
    linkdest="--link-dest=$BACKUP_BASE/last$dst"
  fi

  echo "-> Copia iniziale da $src a $dst"
  do_it rsync -a -P --info=progress2 --no-inc-recursive $linkdest "$src/" "$dst/"
  echo "=> Backup completato per: $dst"

  echo "-> Pulizia file obsoleti in $dst"
  do_it rsync -a --delete --dry-run $linkdest "$src/" "$dst/"
  read -rp "Procedere con cancellazione file non più presenti? [y/N]: " confirm_delete
  if [[ "$confirm_delete" =~ ^[yY]$ ]]; then
    do_it rsync -a --delete $linkdest "$src/" "$dst/"
  else
    echo "Cancellazione saltata."
  fi

  echo "-> Verifica SHA256 parallela..."
  export SRC_BASE="$src" DST_BASE="$dst"
  find "$src" -type f -print0 | xargs -0 -n1 -P"$(nproc)" bash -c '
    src_file="$1"; rel="${src_file#$SRC_BASE}"; dest_file="$DST_BASE$rel"
    [[ -f "$dest_file" ]] || { echo "[ERROR] Missing: $dest_file"; exit 1; }
    src_hash=$(sha256sum "$src_file" | cut -d" " -f1)
    dst_hash=$(sha256sum "$dest_file" | cut -d" " -f1)
    [[ "$src_hash" == "$dst_hash" ]] || { echo "[ERROR] Checksum mismatch: $src_file"; exit 1; }
  ' _
}

# === FUNZIONI DI BACKUP PER OGNI MODULO ===
backup_servarr() {
  echo "== Backup Servarr apps =="
  for svc in radarr sonarr plexmediaserver notifiarr; do
    local src="$BTRFS_MNT/var/lib/$svc"
    local dst="$BACKUP_TMP/servarr_$svc"
    if [[ -d "$src" ]]; then
      backup_and_verify "$src" "$dst"
    else
      echo "[WARN] Directory non trovata: $src"
      read -rp "Vuoi continuare senza backup di $svc? [y/N]: " cont
      [[ "$cont" =~ ^[yY]$ ]] || { echo "Interrotto su richiesta."; exit 1; }
    fi
  done
}

backup_users() {
  echo "== Backup Utenti qBittorrent & NoMachine =="
  for homedir in /home/*; do
    [[ -d "$homedir" ]] || continue
    user=$(basename "$homedir")
    for sub in .config/qBittorrent .local/share/qBittorrent .nx/config Documents/NoMachine; do
      src="$homedir/$sub"
      suffix=$(echo "$sub" | tr '/' '_')
      dst="$BACKUP_TMP/qbt_${user}_$suffix"
      if [[ -d "$src" ]]; then
        backup_and_verify "$src" "$dst"
      else
        echo "[WARN] Directory non trovata: $src"
        read -rp "Vuoi continuare senza backup di $src? [y/N]: " cont
        [[ "$cont" =~ ^[yY]$ ]] || { echo "Interrotto su richiesta."; exit 1; }
      fi
    done
  done
}

backup_nx_server() {
  echo "== Backup NoMachine server =="
  for src in /usr/NX/etc /etc/NX; do
    dst="$BACKUP_TMP/nx_$(basename "$src")"
    if [[ -d "$src" ]]; then
      backup_and_verify "$src" "$dst"
    else
      echo "[WARN] Directory non trovata: $src"
      read -rp "Vuoi continuare senza backup di $src? [y/N]: " cont
      [[ "$cont" =~ ^[yY]$ ]] || { echo "Interrotto su richiesta."; exit 1; }
    fi
  done
}

backup_misc() {
  echo "== Backup config system =="
  [[ -f "$BTRFS_MNT/etc/fstab" ]] && do_it cp "$BTRFS_MNT/etc/fstab" "$BACKUP_TMP/fstab.btrfs"
  [[ -f "$LOGFILE" ]] && do_it cp "$LOGFILE" "$BACKUP_TMP/"
}

# === MOUNT DISPOSITIVI ===
BACKUP_TMP=$(mktemp -d)
mkdir -p "$USB_MNT" "$BTRFS_MNT"
echo "Dispositivi disponibili:"; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'sd|nvme'
read -rp "Device USB (es: sdb1): " d; USB_DEV="/dev/${d##*/}"
[[ -b "$USB_DEV" ]] || { echo "[ERROR] Invalid device"; exit 1; }
do_it mount "$USB_DEV" "$USB_MNT"
do_it vgchange -ay
do_it mount -o subvol=@ "$BASE_DEVICE" "$BTRFS_MNT"

# === SOLO ROLLBACK? ===
if [[ "$BACKUP_ONLY" == "rollback" ]]; then
  read -rp "Vuoi procedere con rollback snapshot? [y/N]: " confirm
  if [[ "$confirm" =~ ^[yY]$ ]]; then
    echo "=== Rollback snapshot ==="
    do_it umount "$BTRFS_MNT"
    do_it mount "$BASE_DEVICE" "$BTRFS_MNT"
    btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk '{print "ID:"$2,"Path:"$NF}'
    read -rp "ID snapshot: " sid
    path=$(btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk -v i="$sid" '$2==i{print $NF}')
    do_it btrfs subvolume delete "$BTRFS_MNT/@"
    do_it btrfs subvolume snapshot "$BTRFS_MNT/@snapshots/$path" "$BTRFS_MNT/@"
    echo "Snapshot $sid ripristinato. Riavvia il sistema."
  else
    echo "Rollback annullato."
  fi
  exit 0
fi

# === ESECUZIONE BACKUP ===
[[ "$RESTORE_ONLY" == false ]] && {
  [[ "$BACKUP_ONLY" == "all" || "$BACKUP_ONLY" == "servarr" ]] && backup_servarr
  [[ "$BACKUP_ONLY" == "all" || "$BACKUP_ONLY" == "users" ]] && backup_users
  [[ "$BACKUP_ONLY" == "all" || "$BACKUP_ONLY" == "nx" ]] && backup_nx_server
  [[ "$BACKUP_ONLY" == "all" || "$BACKUP_ONLY" == "misc" ]] && backup_misc
}

# === ARCHIVIAZIONE ===
package_archive() {
  local ts=$(date +'%Y%m%d_%H%M') arch="backup_arr_$ts.tar"
  do_it tar -cpf "$BACKUP_TMP/$arch" -C "$BACKUP_TMP" .
  do_it sha256sum "$BACKUP_TMP/$arch" > "$BACKUP_TMP/$arch.sha256"
  do_it zstd -19 -f "$BACKUP_TMP/$arch"
  do_it mv "$BACKUP_TMP/$arch.zst" "$USB_MNT/"
  do_it mv "$BACKUP_TMP/$arch.sha256" "$USB_MNT/"
  echo "Archivio creato e spostato su USB"
  if [[ "$INCREMENTAL" == true ]]; then do_it rm -f "$BACKUP_BASE/last"; do_it ln -s "$USB_MNT/$arch.zst" "$BACKUP_BASE/last"; fi
}
package_archive

echo "Script completato con successo."
