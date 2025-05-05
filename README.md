# Debian BTRFS ARR Toolkit

![Version](https://img.shields.io/badge/version-1.0-blue.svg) ![License](https://img.shields.io/badge/license-MIT-green.svg) ![ShellCheck](https://img.shields.io/badge/shellcheck-passed-brightgreen)

Toolkit completo per backup e ripristino di configurazioni e servizi (Radarr, Sonarr, Plex, Notifiarr) su Debian con filesystem BTRFS.

**Creato da Faginux & ChatGPT (OpenAI)**

---

## 📦 Contenuto

- `backup_arr.sh`: script di backup completo con compressione ZSTD, checksum, opzione rollback snapshot
- `restore_arr.sh`: script di ripristino completo con reinstallazione automatica servizi, ripristino configurazioni, confronto fstab interattivo
- `launcher_arr.sh`: script di avvio rapido per backup/ripristino/aggiornamento
- `LICENSE`: licenza MIT
- `README.md`: questa documentazione

## 🚀 Avvio rapido

Per eseguire direttamente senza scaricare manualmente:

```bash
bash <(curl -s https://tinyurl.com/deb-brarr)
```

## ✨ Funzionalità

✅ Backup completo configurazioni Radarr, Sonarr, Plex, Notifiarr  
✅ Compressione ZSTD massima  
✅ Checksum SHA256 integrato  
✅ Ripristino configurazioni e permessi corretti  
✅ Ripristino /etc/fstab con confronto `diff` e conferma interattiva  
✅ Reinstallazione automatica servizi mancanti  
✅ Rollback snapshot BTRFS interattivo  
✅ Launcher unico per gestire tutto

## 📄 Esempio d’uso

1. Collega una USB e avvia lo script launcher:
   ```bash
   bash <(curl -s https://tinyurl.com/deb-brarr)
   ```
2. Seleziona **Esegui Backup** o **Esegui Ripristino** dal menu interattivo
3. Segui le istruzioni a schermo

## 📌 Requisiti

- Debian 12 o superiore
- Filesystem BTRFS
- Volume `/dev/mapper/VGO-LGO`
- Comandi: `btrfs`, `tar`, `zstd`, `sha256sum`, `curl`, `wget`, `systemctl`, `diff`

## 🤝 Contribuire

Pull request e segnalazioni benvenute! Contattami su GitHub [Faginux](https://github.com/Faginux).

## 📝 Licenza

MIT – vedi file LICENSE
