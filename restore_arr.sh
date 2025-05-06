#!/bin/bash
VERSION="1.1"

# ==============================================================================
# restore_arr.sh - Script di ripristino configurazioni e servizi
# Creato da Oscar & ChatGPT (OpenAI)
# Ripristina Radarr, Sonarr, Plex, Notifiarr, qBittorrent, NoMachine, configurazioni e permessi
# con controllo dipendenze essenziali, verifica integrità, confronto fstab, log dettagliato e stato finale dei servizi
# ==============================================================================

set -e  # Ferma lo script se un comando fallisce
LOGFILE="./restore_log.txt"  # Log di output
exec > >(tee -a "$LOGFILE") 2>&1  # Duplica output su log e console

echo "=== Avvio ripristino configurazioni e servizi: $(date) ==="

# === VERIFICA COMANDI ESSENZIALI ===
# Controlla la presenza di comandi fondamentali e ne propone l'installazione se mancanti
missing_cmds=()
for cmd in lsblk tar sha256sum zstd awk systemctl rsync diff; do
  if ! command -v "$cmd" &>/dev/null; then
    missing_cmds+=("$cmd")
  fi
done

if [ ${#missing_cmds[@]} -ne 0 ]; then
  echo "ATTENZIONE: I seguenti comandi essenziali non sono installati: ${missing_cmds[*]}"
  read -p "Vuoi installarli adesso? (y/N): " conferma_comandi
  if [[ "$conferma_comandi" =~ ^[yY]$ ]]; then
    echo "Installazione dei pacchetti necessari..."
    # Determina i pacchetti corrispondenti ai comandi mancanti
    pkgs=()
    for cmd in "${missing_cmds[@]}"; do
      case "$cmd" in
        lsblk) pkgs+=("util-linux") ;;
        tar) pkgs+=("tar") ;;
        sha256sum) pkgs+=("coreutils") ;;
        zstd) pkgs+=("zstd") ;;
        awk) pkgs+=("gawk") ;;  # assicura che awk sia disponibile
        systemctl) pkgs+=("systemd") ;;
        rsync) pkgs+=("rsync") ;;
        diff) pkgs+=("diffutils") ;;
      esac
    done
    # Tenta l'installazione con apt, con fallback (update) in caso di errore
    if ! sudo apt install -y "${pkgs[@]}"; then
      echo "Aggiornamento lista pacchetti e ritento l'installazione..."
      sudo apt update && sudo apt install -y "${pkgs[@]}" || {
        echo "Errore: impossibile installare i comandi essenziali."
        exit 1
      }
    fi
    echo "Tutti i comandi essenziali sono installati."
  else
    echo "Installazione dei comandi essenziali annullata. Impossibile proseguire."
    exit 1
  fi
fi

# === FUNZIONE PER CREARE UTENTE E GRUPPO ===
create_user_and_group(){
  local user=$1 grp=$2 extra=${3:-}
  # Controlla se il gruppo esiste, altrimenti lo crea
  if ! getent group "$grp" &>/dev/null; then sudo groupadd "$grp"; fi
  # Controlla se l'utente esiste, altrimenti lo crea nel gruppo primario
  if ! id "$user" &>/dev/null 2>&1; then sudo useradd --system --no-create-home --ingroup "$grp" "$user"; fi
  # Se è specificato un gruppo secondario, aggiunge l'utente anche lì
  if [ -n "$extra" ]; then sudo usermod -a -G "$extra" "$user"; fi
}

# === CREAZIONE UTENTI e GRUPPI ===
create_user_and_group radarr plex media    # radarr in plex+media
echo "Utente radarr pronto"
create_user_and_group sonarr plex media    # sonarr in plex+media
echo "Utente sonarr pronto"
create_user_and_group plex plex media      # plex in plex+media
echo "Utente plex pronto"
create_user_and_group notifiarr notifiarr media  # notifiarr in notifiarr+media
echo "Utente notifiarr pronto"
echo "Utenti e gruppi verificati o creati"

# === INSTALLAZIONE SERVIZI SE MANCANTI ===
for svc in radarr sonarr; do
  if ! systemctl status "$svc" >/dev/null 2>&1; then
    echo "Installazione $svc..."
    curl -s https://raw.githubusercontent.com/Servarr/servarr-installer/main/servarr_installer.sh | sudo bash -s -- "$svc"
  else
    echo "$svc già installato"
  fi
done

if ! systemctl status plexmediaserver >/dev/null 2>&1; then
  echo "Installazione Plex..."
  wget -q https://downloads.plex.tv/plex-media-server-new/plexmediaserver.deb -O /tmp/plex.deb
  sudo apt install -y /tmp/plex.deb
else
  echo "Plex già installato"
fi

if ! systemctl status notifiarr >/dev/null 2>&1; then
  echo "Installazione Notifiarr..."
  curl -s https://golift.io/repo.sh | sudo bash -s - notifiarr
else
  echo "Notifiarr già installato"
fi

# === BACKUP e CONFRONTO FSTAB ===
echo "Creo una copia dell'attuale /etc/fstab sul Desktop..."
mkdir -p "$HOME/Desktop"
if [ -f /etc/fstab ]; then
  cp /etc/fstab "$HOME/Desktop/fstab.attuale.backup.$(date +%Y%m%d_%H%M)"
  echo "Backup salvato su $HOME/Desktop"
fi

echo "Confronto fstab attuale vs backup:"
diff_output=$(diff -u /etc/fstab "$TEMP/fstab" || true)
if [ -n "$diff_output" ]; then
  echo "$diff_output"
  echo "$diff_output" > "$HOME/Desktop/fstab.diff.$(date +%Y%m%d_%H%M).txt"
else
  echo "(Nessuna differenza trovata)"
fi

read -p "Vuoi sovrascrivere /etc/fstab con quello del backup? (y/N): " conferma_fstab
if [[ "$conferma_fstab" =~ ^[yY]$ ]]; then
  sudo cp "$TEMP/fstab" /etc/fstab
  echo "/etc/fstab ripristinato dal backup."
else
  echo "Ripristino fstab saltato."
fi

# === RIPRISTINO CONFIGURAZIONI ===
echo "Arresto servizi per ripristino sicuro..."
sudo systemctl stop radarr sonarr plexmediaserver notifiarr nxserver || true

echo "Ripristino configurazioni..."
sudo cp -a "$TEMP/radarr/."            /var/lib/radarr/
sudo cp -a "$TEMP/sonarr/."            /var/lib/sonarr/
sudo cp -a "$TEMP/plexmediaserver/."   /var/lib/plexmediaserver/
sudo cp -a "$TEMP/etc_notifiarr/."     /etc/notifiarr/
sudo cp -a "$TEMP/var_log_notifiarr/." /var/log/notifiarr/
sudo cp -a "$TEMP/qbt_config/."        "$HOME/.config/qBittorrent/"
sudo cp -a "$TEMP/qbt_data/."          "$HOME/.local/share/qBittorrent/"
sudo cp -a "$TEMP/nx_config/."         "$HOME/.nx/config/"
sudo cp -a "$TEMP/nx_sessions/."       "$HOME/Documents/NoMachine/"
sudo cp -a "$TEMP/nx_server_etc/."     /usr/NX/etc/
sudo cp -a "$TEMP/nx_etc/."            /etc/NX/

# === PERMESSI ===
echo "Impostazione permessi..."
sudo chown -R radarr:plex          /var/lib/radarr
sudo chown -R sonarr:plex          /var/lib/sonarr
sudo chown -R plex:plex            /var/lib/plexmediaserver
sudo chown -R notifiarr:notifiarr  /etc/notifiarr /var/log/notifiarr
sudo chown -R $USER:$USER          "$HOME/.config/qBittorrent" "$HOME/.local/share/qBittorrent" \
                                   "$HOME/.nx/config" "$HOME/Documents/NoMachine"
sudo chown -R root:root            /usr/NX/etc /etc/NX
sudo chmod -R 755                  /var/lib/radarr /var/lib/sonarr /var/lib/plexmediaserver \
                                   /etc/notifiarr /var/log/notifiarr /usr/NX/etc /etc/NX

# === RIAVVIO SERVIZI ===
echo "Riavvio dei servizi..."
sudo systemctl start radarr sonarr plexmediaserver notifiarr nxserver || true

echo "=== Stato finale dei servizi ==="
for s in radarr sonarr plexmediaserver notifiarr nxserver; do
  echo "--- $s ---"
  sudo systemctl status "$s" --no-pager || true
done

echo "=== Ripristino completato con successo: $(date) ==="
