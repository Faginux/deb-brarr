#!/bin/bash set -e

=== Debian BTRFS ARR Control - Restore Script ===

Creato da Oscar & ChatGPT

Descrizione: Ripristina Radarr, Sonarr, Plex, Notifiarr, qBittorrent e NoMachine da backup.

VERSION="1.2"

echo "=== Debian BTRFS ARR Control - Restore Script ===" echo "Creato da Oscar & ChatGPT" echo

Check automatico se lo script non è avviato come root, lo riavvia con sudo

if [[ "$EUID" -ne 0 ]]; then echo "Lo script richiede privilegi di root. Riavvio con sudo..." exec sudo bash "$0" "$@" fi

Funzione per ripristino di un singolo servizio

restore_service() { local name="$1" local backup_dir="$2" local target_dir="$3"

echo "Inizio ripristino per: $name"
if [ ! -d "$backup_dir" ]; then
    echo "⚠️ Attenzione: la directory di backup $backup_dir non esiste. Salto $name."
    return
fi

mkdir -p "$target_dir"
rsync -aHAX --info=progress2 "$backup_dir/" "$target_dir/"

echo "✅ Ripristino completato per $name."

# Verifica integrità se esiste SHA256SUMS
if [ -f "$backup_dir/SHA256SUMS" ]; then
    echo "Verifica checksum SHA256 per $name..."
    (cd "$target_dir" && sha256sum -c "$backup_dir/SHA256SUMS" || echo "⚠️ Alcuni file potrebbero non combaciare.")
fi

}

Selezione del dispositivo di backup

echo "Dispositivi disponibili:" lsblk -p -o NAME,SIZE,TYPE,MOUNTPOINT read -rp "Inserisci il device su cui è presente il backup (esempio: /dev/sdX1): " usb_dev

mountpoint="/mnt/usb" mkdir -p "$mountpoint"

Controllo se già montato

if mount | grep -q "$mountpoint"; then echo "⚠️ $mountpoint è già montato. Procedo senza montare di nuovo." else mount "$usb_dev" "$mountpoint" fi

backup_root="$mountpoint/arr_backup"

Ripristino servizi

restore_service "Radarr" "$backup_root/radarr" "/var/lib/radarr" restore_service "Sonarr" "$backup_root/sonarr" "/var/lib/sonarr" restore_service "Plex" "$backup_root/plex" "/var/lib/plexmediaserver" restore_service "Notifiarr" "$backup_root/notifiarr" "/etc/notifiarr" restore_service "qBittorrent (utente corrente)" "$backup_root/qbittorrent" "$HOME/.local/share/qBittorrent" restore_service "NoMachine (utente corrente)" "$backup_root/nomachine" "$HOME/.nx"

Ripristino fstab

if [ -f "$backup_root/fstab/fstab" ]; then echo "Backup di sicurezza dell'attuale /etc/fstab in corso (salvato sul Desktop)..." cp /etc/fstab "$HOME/Desktop/fstab.bak_$(date +%Y%m%d_%H%M%S)"

echo "Differenze tra fstab attuale e backup:"
diff -u /etc/fstab "$backup_root/fstab/fstab" || true

read -rp "Vuoi sovrascrivere /etc/fstab con la versione del backup? [s/N]: " confirm_fstab
if [[ "$confirm_fstab" =~ ^([sSyY])$ ]]; then
    cp "$backup_root/fstab/fstab" /etc/fstab
    echo "✅ /etc/fstab ripristinato."
else
    echo "Sovrascrittura di /etc/fstab annullata."
fi

fi

Fine script

echo "✅ Tutti i ripristini sono stati completati."
