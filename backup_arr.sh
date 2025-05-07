#!/bin/bash
set -e

# === Debian BTRFS ARR Control - Backup Script ===
# Creato da Oscar & ChatGPT
# Descrizione: Effettua il backup completo di Radarr, Sonarr, Plex, Notifiarr, qBittorrent e NoMachine,
# più altre cartelle configurabili. Opzionale: rollback da snapshot dopo backup.
VERSION="1.2"

echo "=== Debian BTRFS ARR Control - Backup Script ==="
echo "Creato da Oscar & ChatGPT"
echo

# Check automatico se lo script non è avviato come root, lo riavvia con sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "Lo script richiede privilegi di root. Riavvio con sudo..."
    exec sudo bash "$0" "$@"
fi

# Funzione per montare in modalità RW se il file system è in RO
check_rw_mount() {
    local mount_point=$1
    if mount | grep -q "${mount_point}.*\bro\b"; then
        echo "Il filesystem su $mount_point è montato in sola lettura."
        read -rp "Vuoi rimontare in modalità RW forzata? [s/N]: " confirm
        if [[ "$confirm" =~ ^([sSyY])$ ]]; then
            mount -o remount,rw "$mount_point" || echo "⚠️ Rimontaggio fallito, continuo comunque..."
        else
            echo "Proseguo senza rimontare."
        fi
    fi
}

# Funzione per backup di un singolo servizio
backup_service() {
    local name="$1"
    local source_dir="$2"
    local backup_dir="$3"

    echo "Inizio backup per: $name"
    if [ ! -d "$source_dir" ]; then
        echo "⚠️ Attenzione: la directory $source_dir non esiste. Salto $name."
        read -rp "Vuoi continuare lo script? [S/n]: " continue_choice
        if [[ "$continue_choice" =~ ^([nN])$ ]]; then
            echo "Backup interrotto su richiesta."
            exit 1
        else
            return
        fi
    fi

    mkdir -p "$backup_dir"
    rsync -aHAX --info=progress2 "$source_dir/" "$backup_dir/"

    echo "✅ Copia completata per $name."

    # Hash di verifica
    echo "Genero checksum SHA256 per $name..."
    (cd "$backup_dir" && find . -type f -exec sha256sum {} \; > SHA256SUMS)

    echo "👉 Vuoi eliminare file non più presenti nella sorgente (sincronizzazione dura)?"
    read -rp "Procedere con la cancellazione? [s/N]: " delete_choice
    if [[ "$delete_choice" =~ ^([sSyY])$ ]]; then
        rsync -aHAX --delete "$source_dir/" "$backup_dir/"
        echo "✅ Sincronizzazione completata con eliminazione file obsoleti per $name."
    else
        echo "Nessuna eliminazione eseguita per $name."
    fi
}

# Selezione del dispositivo di backup
echo "Dispositivi disponibili:"
lsblk -p -o NAME,SIZE,TYPE,MOUNTPOINT
read -rp "Inserisci il device su cui montare la destinazione backup (esempio: /dev/sdX1): " usb_dev

mountpoint="/mnt/usb"
mkdir -p "$mountpoint"

# Controllo se già montato
if mount | grep -q "$mountpoint"; then
    echo "⚠️ $mountpoint è già montato. Procedo senza montare di nuovo."
else
    mount "$usb_dev" "$mountpoint"
fi

# Directory di destinazione backup
backup_root="$mountpoint/arr_backup"
mkdir -p "$backup_root"

# Controllo RW sulla destinazione
check_rw_mount "$mountpoint"

# Backup di tutti i servizi
backup_service "Radarr" "/var/lib/radarr" "$backup_root/radarr"
backup_service "Sonarr" "/var/lib/sonarr" "$backup_root/sonarr"
backup_service "Plex" "/var/lib/plexmediaserver" "$backup_root/plex"
backup_service "Notifiarr" "/etc/notifiarr" "$backup_root/notifiarr"
backup_service "qBittorrent (utente corrente)" "$HOME/.local/share/qBittorrent" "$backup_root/qbittorrent"
backup_service "NoMachine (utente corrente)" "$HOME/.nx" "$backup_root/nomachine"
backup_service "fstab" "/etc/fstab" "$backup_root/fstab"

echo "✅ Backup completo terminato."

# Opzione rollback
echo
echo "Vuoi eseguire subito un rollback da snapshot?"
select opt in "Sì, procedi con rollback" "No, esci"; do
    case $REPLY in
        1)
            echo "Avvio procedura di rollback..."
            # Controllo subvolume
            mountpoint_btrfs="/mnt/btrfs"
            mkdir -p "$mountpoint_btrfs"
            echo "Dispositivi BTRFS disponibili:"
            lsblk -p -o NAME,SIZE,TYPE,MOUNTPOINT
            read -rp "Inserisci il device BTRFS (esempio: /dev/nvme0n1pX): " btrfs_dev
            mount -o subvolid=5 "$btrfs_dev" "$mountpoint_btrfs"

            echo "Snapshot disponibili:"
            btrfs subvolume list "$mountpoint_btrfs/@snapshots"

            read -rp "Inserisci ID della snapshot da ripristinare: " snap_id

            snap_path=$(btrfs subvolume list "$mountpoint_btrfs/@snapshots" | grep "ID $snap_id " | awk '{for(i=9;i<=NF;++i) printf "%s ", $i; print ""}' | xargs)

            if [ -z "$snap_path" ]; then
                echo "❌ Snapshot ID non trovato. Uscita."
                umount "$mountpoint_btrfs"
                exit 1
            fi

            echo "⚠️ ATTENZIONE: Stai per eseguire un rollback con la snapshot: $snap_path"
            read -rp "Confermi il rollback? [s/N]: " confirm_rb
            if [[ "$confirm_rb" =~ ^([sSyY])$ ]]; then
                # Pulizia della root attuale
                echo "Pulizia del subvolume root..."
                mount -o subvol=@ "$btrfs_dev" "$mountpoint_btrfs/@"
                rm -rf "$mountpoint_btrfs/@/"{*,.*} 2>/dev/null || true

                echo "Ripristino snapshot..."
                btrfs send "$mountpoint_btrfs/$snap_path" | btrfs receive "$mountpoint_btrfs/@"

                echo "✅ Rollback completato!"
            else
                echo "Rollback annullato."
            fi

            umount "$mountpoint_btrfs"
            ;;
        2)
            echo "Uscita completata."
            ;;
        *)
            echo "Opzione non valida."
            ;;
    esac
    break
done

# Fine script
echo "✅ Tutte le operazioni sono state completate."
