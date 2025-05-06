#!/bin/bash
set -e

echo "=== Debian BTRFS ARR Control ==="
echo "Creato da Oscar & ChatGPT"
echo

# Check per comandi essenziali, con opzione di installazione se mancanti
for cmd in curl chmod; do
  if ! command -v "$cmd" > /dev/null; then
    echo "Il comando '$cmd' non è installato."
    read -p "Vuoi installare '$cmd' automaticamente? [s/N]: " -r risposta
    if [[ "$risposta" =~ ^([sSyY])$ ]]; then
      if command -v apt > /dev/null; then
        sudo apt update && sudo apt install -y "$cmd"
      elif command -v dnf > /dev/null; then
        sudo dnf install -y "$cmd"
      elif command -v pacman > /dev/null; then
        sudo pacman -Sy --noconfirm "$cmd"
      else
        echo "Errore: gestore pacchetti non supportato. Installa '$cmd' manualmente."
        exit 1
      fi
    else
      echo "Errore: '$cmd' richiesto per continuare."
      exit 1
    fi
  fi
done

GITHUB_URL="https://raw.githubusercontent.com/Faginux/deb-brarr/main"

fetch_remote_version() {
  local f="$1"
  curl -fsSL "$GITHUB_URL/$f" | grep -m1 '^VERSION=' | cut -d'"' -f2
}

fetch_local_version() {
  local f="$1"
  grep -m1 '^VERSION=' "$f" 2>/dev/null | cut -d'"' -f2
}

download_script() {
  local f="$1"
  local v_local v_remote
  v_remote=$(fetch_remote_version "$f")
  v_local=$(fetch_local_version "$f")
  echo "$f → versione locale: ${v_local:-none}, versione remota: $v_remote"

  if [[ -z "$v_remote" ]]; then
    echo "ATTENZIONE: impossibile leggere la versione remota di $f. Scarico comunque..."
    curl -fsSL "$GITHUB_URL/$f" -o "$f" || { echo "Errore download $f"; exit 1; }
    chmod +x "$f"
    return
  fi

  if [[ -z "$v_local" ]]; then
    echo "File locale $f mancante o senza VERSION: scarico..."
    curl -fsSL "$GITHUB_URL/$f" -o "$f" || { echo "Errore download $f"; exit 1; }
    chmod +x "$f"
    return
  fi

  if [[ "$v_local" != "$v_remote" ]]; then
    echo "→ Versione remota più recente: scarico nuovo $f..."
    curl -fsSL "$GITHUB_URL/$f" -o "$f" || { echo "Errore download $f"; exit 1; }
    chmod +x "$f"
  else
    echo "→ Versioni uguali: vuoi aggiornare comunque?"
    read -p "Scaricare lo script $f anche se la versione è uguale? [s/N]: " -r confirm
    if [[ "$confirm" =~ ^([sSyY])$ ]]; then
      curl -fsSL "$GITHUB_URL/$f" -o "$f" || { echo "Errore download $f"; exit 1; }
      chmod +x "$f"
    else
      echo "→ Mantengo la versione locale di $f."
    fi
  fi
}

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
        echo "Aggiorno entrambi gli script..."
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
