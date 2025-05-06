
# Debian BTRFS ARR Control

🚀 **Un toolkit completo per backup, ripristino e gestione di snapshot BTRFS su Debian**, con supporto per applicazioni multimediali come **Radarr, Sonarr, Plex, Notifiarr, qBittorrent, NoMachine**.

Creato da **Oscar (Faginux)** & **ChatGPT (OpenAI)**.

---

## 🏆 **Cosa fa questo progetto**

✅ Effettua **backup completi** di:
- Configurazioni e dati di Radarr, Sonarr, Plex, Notifiarr
- Configurazioni utente di qBittorrent e NoMachine (tutti gli utenti presenti)
- Configurazioni server di NoMachine
- File di sistema come `/etc/fstab` e log

✅ Verifica **integrità dei backup con SHA256 (in parallelo)**

✅ Crea un archivio compresso `.tar.zst` con **hash SHA256 incluso**

✅ Salva il backup su **unità USB selezionabile dall’utente**

✅ Permette il **ripristino dei dati** con controllo e conferma

✅ Integra una funzione di **rollback snapshot BTRFS interattivo**

✅ Offre un **launcher interattivo** per scegliere tra backup, ripristino, aggiornamento script

✅ Controlla automaticamente la presenza e la versione degli script, scaricandoli dal repository solo se necessario

✅ Verifica i comandi essenziali (`curl`, `chmod`) e propone di installarli in automatico

---

## 📂 **I tre script principali**

### `backup_arr.sh`
Script principale di **backup**:
- Effettua backup incrementale (opzionale)
- Verifica integrità file
- Archivia e comprime il backup
- Salva su USB
- Esegue rollback snapshot opzionale

### `restore_arr.sh`
Script di **ripristino**:
- Decomprime e ripristina automaticamente tutti i dati
- Verifica hash SHA256 prima dell’estrazione
- Riavvia i servizi dopo il ripristino
- Crea una copia di sicurezza dei file di sistema prima di sovrascriverli

### `launcher_arr.sh`
Un pratico **launcher interattivo**:
- Ti fa scegliere se eseguire backup o ripristino
- Scarica automaticamente gli script aggiornati solo se necessario
- Controlla la versione locale/remota
- Ti propone l’aggiornamento solo se la versione è diversa o su tua conferma

---

## 🖥️ **Come si usa**

### ✅ Per avviare tutto **con un solo comando**, usa:

```bash
bash <(curl -s https://tinyurl.com/launch-arr)
```

> Questo comando scarica ed esegue `launcher_arr.sh` direttamente dal repository.

---

## 🎛️ **Funzionalità avanzate**

- Supporta rollback da snapshot BTRFS interattivo
- Backup multiutente automatico per qBittorrent e NoMachine
- Controllo integrità con SHA256 parallelo (più veloce su directory grandi)
- Comandi eseguiti in modo sicuro con log e messaggi chiari
- Supporta `apt`, `dnf` e `pacman` per installazione automatica delle dipendenze di base

---

## 📋 **Requisiti**

- Debian 12 (o superiore) con filesystem BTRFS
- Subvolumi configurati: `@`, `@home`, `@var`, `@tmp`, `@snapshots`
- `curl`, `chmod`, `rsync`, `tar`, `zstd`, `sha256sum`, `xargs`, `btrfs-progs`, `vgchange`, `awk`, `logrotate`

---

## 📝 **Licenza**

Questo progetto è distribuito sotto licenza **MIT**.

© 2025 Oscar (Faginux) & ChatGPT (OpenAI)

---

## 🤝 **Supporto**

Hai domande o vuoi contribuire? Scrivimi su GitHub oppure apri una issue!

---

**Debian BTRFS ARR Control**: il tuo sistema sempre al sicuro, senza complicazioni.
