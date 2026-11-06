# Notes — Step 2B: firma Android protetta, senza chiavi nel repository

Stato: **pipeline implementata / certificazione release ANCORA BLOCCATA**. Baseline `main@548af3b9fe7dd00b17dc932712c9048fd733d6bf`. Riferimento: issue [#71](https://github.com/riccardopinato/Notes-Ecosistema/issues/71).

## Separazione rigorosa dei canali

**CI da push/PR**: continua a produrre APK/AAB con chiave Android Debug temporanea; artefatti etichettati `CI-ONLY-NOT-FOR-PRODUCTION`. Il gate verifica che il certificato degli APK ABI sia coerente, e che AAB sia firmato con certificato identico. Queste build **NON** devono aggiornare installazioni con dati da conservare e **NON** sono release Play.

**Firma esplicita autorizzata**: solo `workflow_dispatch` su `main` con `production_signed: true`, dopo aver recuperato la **chiave di rilascio/upload originale autorizzata** e determinato il suo SHA-256. Non creare una nuova chiave sostitutiva per aggiornare un'installazione esistente; le firme devono essere compatibili con il percorso di distribuzione. Non caricare chiavi o password su GitHub nel repository.

La pipeline interrompe la build firmata se mancano credenziali, se l'impronta è invalida, se il certificato non coincide con l'identità autorizzata oppure se l'identità rimane `Android Debug`. Gli APK sono verificati con `apksigner`, l'AAB con `jarsigner` e `keytool`. I test `tool/test_release_signing_config.py` verificano la configurazione Gradle fail-closed.

## GitHub Actions Secrets richiesti (da configurare fuori repository)

| Nome | Valore |
| --- | --- |
| `NOTES_ANDROID_KEYSTORE_BASE64` | Keystore esistente approvato, codificato Base64 |
| `NOTES_ANDROID_KEYSTORE_PASSWORD` | Password del keystore |
| `NOTES_ANDROID_KEY_ALIAS` | Alias effettivo |
| `NOTES_ANDROID_KEY_PASSWORD` | Password dell'alias |
| `NOTES_ANDROID_CERT_SHA256` | Impronta SHA-256 **pubblica** del certificato autorizzato, 64 cifre esadecimali |

Non registrare segreti negli issue, nei log o nei file di evidenza. La chiave sul runner è effimera e non è un artefatto scaricabile.

**Play App Signing:** il certificato di upload dell'AAB può essere diverso dal certificato con cui Google Play firma gli APK consegnati all'utente. Un APK firmato con la upload key non è automaticamente compatibile con le installazioni Play.

## Gate che restano aperti

1. Identificare il certificato dell'APK attualmente installato e la titolarità della relativa chiave. Gli APK debug firmati da CI precedenti avevano impronte differenti; una nuova release non li aggiorna automaticamente.
2. Configurare in modo sicuro i segreti **solo dopo** aver verificato l'autorità della chiave. Nessuna chiave privata è disponibile in questa PR.
3. Eseguire una build manuale `production_signed=true` su main e allegare le prove di impronta e formato, senza divulgare password.
4. Verificare un vero aggiornamento **in-place** su Android con archivio sintetico, app ID corretto, versionCode crescente e **nessuna cancellazione dei dati**.
5. Confermare backup/restore crash-safe e il collaudo SAF separatamente: issue [#75](https://github.com/riccardopinato/Notes-Ecosistema/issues/75). Non sostituire automaticamente le installazioni storiche con chiavi incompatibili.

Questa PR non afferma che la firma production sia già attiva e non chiude #71.
