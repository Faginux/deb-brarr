#!/bin/bash
set -e  # Se un comando fallisce, termina immediatamente lo script

# Titolo e autori
echo "=== Debian BTRFS ARR Control ==="
echo "Creato da Oscar & ChatGPT"
echo

# Variabile contenente l'URL base del repository GitHub da cui scaricare gli script
GITHUB_URL="https://raw.githubusercontent.com/Faginux/deb-brarr/main"

# Funzione per scaricare uno script da GitHub
download_script() {
  local f="$1"  # parametro: nome file da scaricare
  echo "Scarico $f da GitHub..."
  # Scarica il file dal repo, salva con nome locale uguale, e controlla eventuali errori
  curl --connect-timeout 10 --max-time 60 -fsSL "$GITHUB_URL/$f" -o "$f" || { echo "Errore: impossibile scaricare $f"; exit 1; }
  chmod +x "$f"  # rende lo script scaricato eseguibile
}

# Ciclo per verificare che gli script backup_arr.sh e restore_arr.sh siano presenti; altrimenti li scarica
for f in backup_arr.sh restore_arr.sh; do
  if [ ! -f "$f" ]; then
    download_script "$f"
  fi
done

# Ciclo principale per mostrare il menu all'utente
while true; do
  echo
  echo "Scegli un'opzione:"
  # 'select' crea un menu numerato per scegliere un'opzione
  select opt in "Esegui Backup" "Esegui Ripristino" "Aggiorna Script" "Esci"; do
    case $REPLY in
      1)
        echo "Avvio backup..."
        exec ./backup_arr.sh  # esegue lo script di backup e sostituisce il processo corrente
        ;;
      2)
        echo "Avvio ripristino..."
        exec ./restore_arr.sh  # esegue lo script di ripristino
        ;;
      3)
        echo "Aggiornamento script da GitHub..."
        # Aggiorna entrambi gli script forzando il download
        for f in backup_arr.sh restore_arr.sh; do
          download_script "$f"
        done
        echo "Aggiornamento completato!"
        break  # torna al menu principale
        ;;
      4)
        echo "Uscita."
        exit 0  # chiude il launcher
        ;;
      *)
        echo "Opzione non valida."  # gestisce input fuori range
        ;;
    esac
  done
done
