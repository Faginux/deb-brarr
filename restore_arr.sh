#!/usr/bin/env bash
set -euo pipefail

BASE_DEVICE="/dev/mapper/VGO-LGO"
BTRFS_MNT="/mnt/btrfs"
USB_MNT="/mnt/usb"
BACKUP_BASE="/backups"
LOGFILE="/var/log/backup_arr.log"
LOGROTATE_CONF="/etc/logrotate.d/backup_arr"
INCREMENTAL=true
ROLLBACK=true
dry=false
BACKUP_ONLY="all"
RESTORE_ONLY=false

require_cmd() { command -v "$1" &>/dev/null || { echo "[ERROR] Missing: $1" >&2; exit 1; } }
for cmd in lsblk vgchange btrfs mktemp rsync tar sha256sum zstd awk getopts logrotate xargs; do require_cmd "$cmd"; done

do_it() {
  if [[ "$dry" == true ]]; then echo "DRY-RUN: $*"; else eval "$*"; fi
  local status=$?
  if [[ $status -ne 0 ]]; then echo "[ERROR] Command failed: $*" >&2; exit $status; fi
}

backup_and_verify() {
  local src="$1" dst="$2" linkdest=""
  mkdir -p "$dst"
  if [[ "$INCREMENTAL" == true && -d "$BACKUP_BASE/last$dst" ]]; then
    linkdest="--link-dest=$BACKUP_BASE/last$dst"
  fi
  echo "-> Backup $src -> $dst"
  do_it rsync -a --delete -P --info=progress2 --no-inc-recursive $linkdest "$src/" "$dst/"
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

BACKUP_TMP=$(mktemp -d)
mkdir -p "$USB_MNT" "$BTRFS_MNT"
echo "Dispositivi disponibili:"; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'sd|nvme'
read -rp "Device USB (es: sdb1): " d; USB_DEV="/dev/${d##*/}"
[[ -b "$USB_DEV" ]] || { echo "[ERROR] Invalid device"; exit 1; }
do_it mount "$USB_DEV" "$USB_MNT"
do_it vgchange -ay
do_it mount -o subvol=@ "$BASE_DEVICE" "$BTRFS_MNT"

[[ "$RESTORE_ONLY" == false ]] && {
  [[ "$BACKUP_ONLY" =~ all|servarr ]] && backup_servarr
  [[ "$BACKUP_ONLY" =~ all|users ]] && backup_users
  [[ "$BACKUP_ONLY" =~ all|nx ]] && backup_nx_server
  [[ "$BACKUP_ONLY" =~ all|misc ]] && backup_misc
}

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

if [[ "$ROLLBACK" == true ]]; then
  echo "=== Rollback snapshot ==="
  do_it umount "$BTRFS_MNT"
  do_it mount "$BASE_DEVICE" "$BTRFS_MNT"
  btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk '{print "ID:"$2,"Path:"$NF}'
  read -rp "ID snapshot: " sid
  path=$(btrfs subvolume list "$BTRFS_MNT/@snapshots" | awk -v i="$sid" '$2==i{print $NF}')
  do_it btrfs subvolume delete "$BTRFS_MNT/@"
  do_it btrfs subvolume snapshot "$BTRFS_MNT/@snapshots/$path" "$BTRFS_MNT/@"
  echo "Snapshot $sid ripristinato. Riavvia il sistema."
fi

echo "Script completato con successo."
