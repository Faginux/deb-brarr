restore_interattivo_install_notifiarr.sh
#!/bin/bash
set -e
LOGFILE="./restore_log.txt"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== Avvio ripristino configurazioni e servizi: $(date) ==="
create_user_and_group(){
  local user=$1 grp=$2 extra=${3:-}
  if ! getent group "$grp" &>/dev/null; then sudo groupadd "$grp"; fi
  if ! id "$user" &>/dev/null 2>&1; then sudo useradd --system --no-create-home --ingroup "$grp" "$user"; fi
  if [ -n "$extra" ]; then sudo usermod -a -G "$extra" "$user"; fi
}
create_user_and_group radarr plex
create_user_and_group sonarr plex
create_user_and_group plex plex
create_user_and_group notifiarr notifiarr
echo "Utenti e gruppi verificati o creati"
if ! systemctl status radarr >/dev/null 2>&1; then
  echo "Installazione Radarr..."
  curl -s https://raw.githubusercontent.com/Servarr/servarr-installer/main/servarr_installer.sh | sudo bash -s -- radarr
else
  echo "Radarr già installato"
fi
if ! systemctl status sonarr >/dev/null 2>&1; then
  echo "Installazione Sonarr..."
  curl -s https://raw.githubusercontent.com/Servarr/servarr-installer/main/servarr_installer.sh | sudo bash -s -- sonarr
else
  echo "Sonarr già installato"
fi
if ! systemctl status plexmediaserver >/dev/null 2>&1; then
  echo "Installazione Plex..."
  wget https://downloads.plex.tv/plex-media-server-new/plexmediaserver.deb -O /tmp/plex.deb
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
BKP_DIR="$HOME/Scaricati"
echo "Archivi di backup trovati in $BKP_DIR:"
ls "$BKP_DIR"/*.tar.zst || { echo "Nessun archivio trovato"; exit 1; }
read -p "Inserisci il nome dell'archivio (.tar.zst): " ARC
ARC_PATH="$BKP_DIR/$ARC"
[ ! -f "$ARC_PATH" ] && { echo "Archivio non trovato: $ARC_PATH"; exit 1; }
TEMP="/tmp/restore_temp"
sudo rm -rf "$TEMP" && sudo mkdir -p "$TEMP"
echo "Estrazione dell'archivio..."
sudo tar -I zstd -xf "$ARC_PATH" -C "$TEMP"
echo "Verifica checksum SHA256..."
sha256sum -c "$TEMP"/*.sha256 || { echo "Errore: checksum fallito"; exit 1; }
echo "Checksum OK"
echo "Creo una copia dell'attuale /etc/fstab sulla Desktop..."
mkdir -p "$HOME/Desktop"
if [ -f /etc/fstab ]; then
  cp /etc/fstab "$HOME/Desktop/fstab.attuale.backup.$(date +%Y%m%d_%H%M)"
  echo "Backup salvato su $HOME/Desktop/fstab.attuale.backup.*"
fi
# === MOSTRA DIFFERENZE PRIMA DI SOVRASCRIVERE ===
echo "Confronto tra fstab attuale e quello del backup:"
diff_output=$(diff -u /etc/fstab "$TEMP/fstab" || true)
if [ -n "$diff_output" ]; then
  echo "$diff_output"
  echo "$diff_output" > "$HOME/Desktop/fstab.diff.$(date +%Y%m%d_%H%M).txt"
  echo "Differenze salvate su Desktop in fstab.diff.*.txt"
else
  echo "(Nessuna differenza trovata)"
fi
read -p "Vuoi sovrascrivere /etc/fstab con quello del backup? (y/N): " conferma_fstab
if [[ "$conferma_fstab" == "y" || "$conferma_fstab" == "Y" ]]; then
  echo "Ripristino /etc/fstab dal backup..."
  sudo cp "$TEMP/fstab" /etc/fstab
  echo "/etc/fstab ripristinato dal backup."
else
  echo "Ripristino /etc/fstab saltato."
fi
echo "Arresto servizi per ripristino sicuro..."
sudo systemctl stop radarr sonarr plexmediaserver notifiarr
echo "Ripristino delle configurazioni nelle directory corrette..."
sudo cp -a "$TEMP/radarr/." /var/lib/radarr/
sudo cp -a "$TEMP/sonarr/." /var/lib/sonarr/
sudo cp -a "$TEMP/plexmediaserver/." /var/lib/plexmediaserver/
sudo cp -a "$TEMP/etc_notifiarr/." /etc/notifiarr/
sudo cp -a "$TEMP/var_log_notifiarr/." /var/log/notifiarr/
echo "Impostazione permessi..."
sudo chown -R radarr:plex /var/lib/radarr
sudo chown -R sonarr:plex /var/lib/sonarr
sudo chown -R plex:plex /var/lib/plexmediaserver
sudo chown -R notifiarr:notifiarr /etc/notifiarr /var/log/notifiarr
sudo chmod -R 755 /var/lib/radarr /var/lib/sonarr /var/lib/plexmediaserver /etc/notifiarr /var/log/notifiarr
echo "Riavvio dei servizi..."
sudo systemctl start radarr sonarr plexmediaserver notifiarr
echo "=== Stato finale dei servizi ==="
for s in radarr sonarr plexmediaserver notifiarr; do
  echo "--- $s ---"
  sudo systemctl status "$s" --no-pager
done
echo "=== Ripristino completato con successo: $(date) ==="
