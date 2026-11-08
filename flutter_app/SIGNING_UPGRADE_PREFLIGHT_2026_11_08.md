# Step 2 · Preflight aggiornamento Android: firma e identità

**Stato:** controllo automatico di evidenze PUBBLICHE implementato; rilascio e aggiornamento su dispositivo NON certificati. Issue #71.

## Prima di provare a installare
1. Recuperare package esatto, versionCode e SHA-256 del certificato di **una build realmente installata** (per APK/split di origine autorizzata; usare `adb shell pm path it.notes.ecosystem.lymlyc`, estrarre il base.apk tramite adb e leggere con `apksigner verify --print-certs`). Non disinstallare e non sostituire app con note reali.
2. Recuperare package, versionCode, certificato e subject del candidato APK tramite `aapt dump badging` / `apksigner verify --print-certs`. Per Play, leggere anche il certificato **App Signing** dalla Play Console: l'upload certificate dell'AAB può differire.
3. Usare `python3 tool/signing_upgrade_preflight.py --installed-package it.notes.ecosystem.lymlyc --candidate-package it.notes.ecosystem.lymlyc --installed-cert <SHA256_INSTALLATO> --candidate-cert <SHA256_CANDIDATO> --installed-code <VERSIONCODE_ATTUALE> --candidate-code <VERSIONCODE_SUPERIORE> --candidate-subject '<SUBJECT_CANDIDATO>' --channel direct`.
4. Per il canale Play, aggiungere `--channel play --play-app-signing-cert <SHA256_FIRMA_APP_PLAY>`; il controllo confronta il certificato realmente distribuito da Google, non assume che la chiave di upload sia quella degli APK installati.
5. In caso di BLOCKED, interrompere il rilascio; verificare chiave storica, tipo di distribuzione e backup, **mai disinstallare come soluzione**.
6. Anche con PREFLIGHT_PASS serve prova su dispositivo fisico Android usando dati sintetici: update in-place, lettura dati prima/dopo, backup e restore, SHA-256 APK, firma, versionCode e log di esito.

Non memorizzare segreti, keystore o password nei repo / issue / log. La CI manuale production_signed esistente è già fail-closed ma può essere avviata solo dopo aver configurato i segreti corretti esternamente e dopo aver identificato la firma autorizzata. Il preflight non recupera da solo informazioni dal telefono, non prova la conservazione dei dati e NON chiude la issue #71.
