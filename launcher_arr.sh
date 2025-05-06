#!/bin/bash
set -e

echo "=== Debian BTRFS ARR Control ==="
echo "Creato da Oscar & ChatGPT"
echo

GITHUB_URL="https://raw.githubusercontent.com/Faginux/deb-brarr/main"

download_script() {
  local f="$1"
  echo "Scarico $f da GitHub..."
  curl -fsSL "$GITHUB_URL/$f" -o "$f" || { echo "Errore: impossibile scaricare $f"; exit 1; }
  chmod +x "$f"
}

# Scarica gli script solo se mancanti
for f in backup_arr.sh restore_arr.sh; do
  if [ ! -f "$f" ]; then
    download_script "$f"
  fi
done

while true; do
  echo
  echo "Scegli un'opzione:"
  select opt in "Esegui Backup" "Esegui Ripristino" "Aggiorna Script" "Esci"; do
    case $REPLY in
      1)
        echo "Avvio backup..."
        exec ./backup_arr.sh
        ;;
      2)
        echo "Avvio ripristino..."
        exec ./restore_arr.sh
        ;;
      3)
        echo "Aggiornamento script da GitHub..."
        for f in backup_arr.sh restore_arr.sh; do
          download_script "$f"
        done
        echo "Aggiornamento completato!"
        break
        ;;
      4)
        echo "Uscita."
        exit 0
        ;;
      *)
        echo "Opzione non valida."
        ;;
    esac
  done
done
