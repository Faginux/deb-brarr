#!/usr/bin/env bash
set -euo pipefail

# ====================================================================================
# backup_arr.sh - Unified Backup and Snapshot Rollback Script
# Creato da Oscar & ChatGPT (OpenAI)
# Effettua backup di Servarr apps, qBittorrent, NoMachine e consente rollback su BTRFS
# ====================================================================================

# --- CONFIGURAZIONE ---
BASE_DEVICE="/dev/mapper/VGO-LGO"       # Dispositivo LVM per BTRFS root
BTRFS_MNT="/mnt/btrfs"                   # Punto di mount temporaneo per BTRFS
USB_MNT="/mnt/usb"                       # Punto di mount per USB
LOGFILE="./backup_arr_$(date +'%Y%m%d_%H%M%S').log"

# --- LOGGING & CLEANUP ---
exec > >(tee -a "$LOGFILE") 2>&1
trap 'echo "[ERROR] Script interrotto! Pulizia..."; cleanup; exit 1' INT TERM ERR

cleanup() {
  umount "$BTRFS_MNT" 2>/dev/null || :
  umount "$USB_MNT" 2>/dev/null || :
  rm -rf "$BACKUP_TMP" || :
}

# --- FUNZIONI UTILITY ---
require_cmd() {
  command -v "$1" &>/dev/null || { echo "[FATAL] Comando non trovato: $1" >&2; exit 1; }
}
retry_rsync() {
  local src=$1 dst=$2
  local tries=3
  while (( tries-- > 0 )); do
    if rsync -a --info=progress2 "$src" "$dst"; then
      return 0
    fi
    echo "[WARN] rsync fallito, ritento... (${tries} rimanenti)"
    sleep 2
  done
  echo "[FATAL] rsync non riuscito dopo più tentativi" >&2; exit 1
}
backup_and_verify() {
  local src=$1 dst=$2
  echo "-> Copio $src -> $dst"
  retry_rsync "$src" "$dst"
  echo "   Verifica integrità SHA256..."
  find "$src" -type f -print0 | while IFS= read -r -d '' file; do
    rel="${file#$src}"
    destfile="$dst$rel"
    if [[ ! -f "$destfile" ]]; then
      echo "[ERROR] File mancante: $destfile" >&2; exit 1
    fi
    src_hash=$(sha256sum "$file" | cut -d' ' -f1)
    dst_hash=$(sha256sum "$destfile" | cut -d' ' -f1)
    [[ "$src_hash" == "$dst_hash" ]] || { echo "[ERROR] Hash mismatch: $file" >&2; exit 1; }
  done
}
check_space() {
  local mnt=$1 need=$2
  local avail=$(df --output=avail "$mnt" | tail -1)
  (( need < avail )) || { echo "[FATAL] Spazio insufficiente su $mnt" >&2; exit 1; }
}

# --- PRE-CHECK ---
# Root
if [[ $(id -u) -ne 0 ]]; then echo "[FATAL] Esegui come root."; exit 1; fi
# Comandi richiesti
for cmd in lsblk vgchange btrfs mktemp rsync tar sha256sum zstd awk; do require_cmd "$cmd"; done
# Crea temp directory
BACKUP_TMP=$(mktemp -d)
# Mount USB selection
echo "Dispositivi di blocco disponibili:"; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'sd|nvme'
read -rp "Seleziona device USB (es: sdb1): " usbdev
USB_DEV="/dev/${usbdev##*/}"
[[ -b "$USB_DEV" ]] || { echo "[FATAL] Device inesistente."; cleanup; exit 1; }
# Montaggi
mkdir -p "$USB_MNT" "$BTRFS_MNT"
mount "$USB_DEV" "$USB_MNT" || { echo "[FATAL] mount USB fallito."; cleanup; exit 1; }
vgchange -ay
mount -o subvol=@ "$BASE_DEVICE" "$BTRFS_MNT" || { echo "[FATAL] mount BTRFS fallito."; cleanup; exit 1; }

# --- BACKUP SERVARR APPS ---
backup_servarr() {
  echo "== Backup Servarr Apps =="
  for svc in radarr sonarr plexmediaserver notifiarr; do
    local src="$BTRFS_MNT/var/lib/$svc"
    local dst="$BACKUP_TMP/servarr_$svc"
    [[ -d "$src" ]] && backup_and_verify "$src" "$dst"
  done
}

# --- BACKUP UTENTI (qBittorrent + NoMachine) ---
backup_users() {
  echo "== Backup Utenti qBittorrent & NoMachine =="
  for homedir in /home/*/; do
    [[ -d "$homedir" ]] || continue
    user=$(basename "$homedir")
    echo "-- [$user] --"
    [[ -d "$homedir/.config/qBittorrent" ]] && backup_and_verify "$homedir/.config/qBittorrent" "$BACKUP_TMP/qbt_${user}_config"
    [[ -d "$homedir/.local/share/qBittorrent" ]] && backup_and_verify "$homedir/.local/share/qBittorrent" "$BACKUP_TMP/qbt_${user}_data"
    [[ -d "$homedir/.nx/config" ]] && backup_and_verify "$homedir/.nx/config" "$BACKUP_TMP/nx_${user}_client"
    [[ -d "$homedir/Documents/NoMachine" ]] && backup_and_verify "$homedir/Documents/NoMachine" "$BACKUP_TMP/nx_${user}_sessions"
  done
}

# --- BACKUP NoMachine SERVER ---
backup_nx_server() {
  echo "== Backup NoMachine Server =="
  [[ -d "/usr/NX/etc" ]] && backup_and_verify "/usr/NX/etc" "$BACKUP_TMP/nx_server_etc"
  [[ -d "/etc/NX"   ]] && backup_and_verify "/etc/NX"   "$BACKUP_TMP/nx_etc"
}

# --- MISC BACKUP (fstab + log) ---
backup_misc() {
  echo "== Backup misc =="
  cp "$BTRFS_MNT/etc/fstab" "$BACKUP_TMP/fstab.btrfs"
  cp "$LOGFILE"            "$BACKUP_TMP/"
}

# --- ARCHIVIAZIONE E COMPRESSIONE ---
package_archive() {
  echo "== Packaging backup =="
  local TS=$(date +'%Y%m%d_%H%M')
  local ARCH="backup_arr_${TS}.tar"
  (cd "$BACKUP_TMP" && tar -cpf "$ARCH" .)
  sha256sum "$BACKUP_TMP/$ARCH" > "$BACKUP_TMP/${ARCH}.sha256"
  zstd -19 -f "$BACKUP_TMP/$ARCH"
  mv "$BACKUP_TMP/${ARCH}.zst" "$USB_MNT/"
  mv "$BACKUP_TMP/${ARCH}.sha256" "$USB_MNT/"
  echo "Backup archiviato e copiato su USB: ${ARCH}.zst"
}

# --- ROLLBACK SNAPSHOT INTERATTIVO ---
rollback_snapshot() {
  read -rp "Vuoi eseguire rollback snapshot? [y/N]: " ans
  [[ "$ans" =~ ^[yY]$ ]] || return
  echo "== Rollback snapshot =="
  umount "$BTRFS_MNT"
  mount "$BASE_DEVICE" "$BTRFS_MNT"
  btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk '{print "ID:"$2,"Path:"$NF}'
  read -rp "Seleziona ID snapshot: " sid
  path=$(btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk -v id="$sid" '$2==id{print $NF}')
  echo "Rollback da: $path"
  btrfs subvolume delete "$BTRFS_MNT/@"
  btrfs subvolume snapshot "$BTRFS_MNT/@snapshots/$path" "$BTRFS_MNT/@"
  umount "$BTRFS_MNT"; vgchange -an
  echo "Rollback completato. Riavviare il sistema."  
}

# --- MAIN ---
backup_servarr
backup_users
backup_nx_server
backup_misc
package_archive
rollback_snapshot
cleanup

echo "=== Script terminato con successo ==="
