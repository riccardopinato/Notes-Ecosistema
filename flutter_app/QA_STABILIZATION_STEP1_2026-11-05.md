# Notes — Step 1, audit tecnico e matrice dei gate (05/11/2026)

**Stato:** audit documentale, inventario repository/CI e campionamento dei test completati; **nessun collaudo fisico o certificazione Play eseguiti in questo step**. Non è una release né una riparazione automatica.

## 0. Provenienza e ambito

- Repository: `riccardopinato/Notes-Ecosistema`.
- Commit sorgente analizzato (prima di questo documento): `main@3cd9062601e58ee4ad8bfb7bb6eb2c96a24b890f`, versione dichiarata `flutter_app/pubspec.yaml: 0.56.3+74`.
- Factory baseline già fissata nel progetto: `riccardopinato/App-Factory-Core@42ad47a9ebacc55ae901ea55a01a6855e320377d`, Master v27 / Golden Index v28. Non reinterpretare Golden DRAFT come certificazioni.
- CI verificata per quel commit: [Flutter Port CI #42060940945](https://github.com/riccardopinato/Notes-Ecosistema/actions/runs/42060940945) = **SUCCESS**; [Deploy Web Preview #42060943570](https://github.com/riccardopinato/Notes-Ecosistema/actions/runs/42060943570) = **SUCCESS**.
- Metodo: inventario della tree GitHub (288 file), lettura delle due workflow, dei 62 file `flutter_app/test/*_test.dart`, sorgenti pertinenti e QA checklist; ispezione effettiva del certificato **APK Signing Block v2** di due APK ARM64 da esecuzioni differenti. Non è un audit esaustivo di ogni ramo dei 138 file Dart né un penetration test.
- Ambito dell'audit: qualità del dato, performance, canvas, documenti/PDF, AI, collaborazione, signing/aggiornamenti e riproducibilità. Il fatto che un test esista non implica copertura del percorso runtime su telefono.

## 1. Inventario effettivo dei controlli

### 1.1 Codice e suite

| Elemento | Evidenza | Interpretazione |
| --- | --- | --- |
| Codice applicativo Flutter | 138 file Dart sotto `flutter_app/lib/` | Fonte attiva, non la precedente linea Kotlin |
| Test Flutter | 62 file sotto `flutter_app/test/` | ~300 chiamate `test(...)` / `testWidgets(...)` conteggiate staticamente |
| Widget test | 14 casi `testWidgets` | 11 in `whiteboard_viewport_test.dart`, gli altri in contrasto/tema/resilienza UI; non sono E2E Android |
| Test Android strumentali/E2E | Nessuna directory `androidTest/`, `integration_test/` o `test_driver/` nella tree | **Non trovati nel repository**, non prova dell'assenza di verifiche manuali esterne |
| Build mobile | CI: analyzer, unit/widget suite, debug APK, release split-per-ABI, 80 MiB accident guard, Play AAB | PASS automatico sul commit base |
| Build web | `.github/workflows/deploy-pages.yml` | Deploy Web Preview PASS su commit base |
| PDF QA | `flutter_app/PDF_TOOLBOX_DEVICE_QA.md` con 12 casi tutti `NOT RUN` | La funzione resta off nella release ordinaria; issue [#70](https://github.com/riccardopinato/Notes-Ecosistema/issues/70) |

L'inventario è costruito da test nel repository: non si attribuiscono arbitrariamente PASS a test non realmente eseguiti. I ~300 sono **casi dichiarati** e non misurano la qualità della copertura o il numero di assert.

### 1.2 Copertura per dominio

| Dominio | Evidenze di test già presenti | Gap realistico / prossimo gate |
| --- | --- | --- |
| **Dati, lifecycle, Trash** | `lifecycle_test.dart`, `reference_lifecycle_test.dart`, `attachment_lifecycle_test.dart`, `note_compatibility_test.dart` | Riapertura dopo kill/crash, recupero orfani, migrazione versionCode, verifica SQLite reale su device |
| **Backup e portabilità** | `disaster_recovery_test.dart` (roundtrip, v1, zip non sicuri), `media_bundle_test.dart`, `open_export_test.dart`, `sync_compatibility_test.dart` | Restore da file vero in storage Android, crash a metà staging, rollback dopo errore I/O, confronto SHA/ID tra versioni |
| **Whiteboard/Ink** | `whiteboard_viewport_test.dart` (11 widget test), `whiteboard_stress_test.dart` (20k/50k points), `visual_ink_shared_test.dart` | Palm rejection e pressione stylus su hardware, jank 60/120 Hz, salvataggio/restore dopo kill; vedi `WHITEBOARD_DEVICE_QA_0_54_3.md` |
| **PDF/OCR/Documenti** | `document_workspace_test.dart`, `document_delta_test.dart`, `pdf_toolbox_bridge_test.dart` (2 test: header e argomenti) | Test nativi con PDF reali sintetici/codec/font/firme e file originali invariati; issue #70 |
| **AI locale e ricerca** | `local_llm_policy_test.dart`, `needle_runtime_test.dart`, `needle_benchmark_test.dart`, `semantic_retrieval_integration_test.dart`, `ml23_local_text_consumer_test.dart` | JNI/Play AI pack e disponibilità AICore su device, qualità IT/EN/ES/FR/DE/PT, memoria/PSS p50/p95 e fallback end-to-end |
| **Project/Planner** | `project_dependency_review_test.dart`, `project_dependency_actions_test.dart`, `project_goal_timeline_test.dart`, `project_workload_guard_test.dart` | Save-time stale revision, ACL/role/account switch, validazione 500/5000 task e UI dopo resume |
| **Shared Spaces/Sync** | `shared_spaces_test.dart` (22 test), `shared_activity_test.dart`, `shared_background_bridge_test.dart`, `sync_compatibility_test.dart` | Collaudo a due dispositivi/rete intermittente, autorizzazioni native, account switch e conflitti nella persistenza reale |
| **Accessibilità/UI** | `light_theme_contrast_test.dart`, `study_card_contrast_test.dart`, `ui_resilience_test.dart` | TalkBack, text scale, rotazione, schermi piccoli, navigazione tastiera e screenshot device |
| **Acquisizione** | `smart_capture_test.dart`, `smart_inbox_source_preview_test.dart`, `smart_inbox_checklist_action_test.dart` | Intent Android con PDF e immagini, URI/revoca permessi, file grandi, lifecycle background, UI di conferma finale |

Le issue di prodotto [#46](https://github.com/riccardopinato/Notes-Ecosistema/issues/46), [#47](https://github.com/riccardopinato/Notes-Ecosistema/issues/47), [#48](https://github.com/riccardopinato/Notes-Ecosistema/issues/48), [#49](https://github.com/riccardopinato/Notes-Ecosistema/issues/49), [#51](https://github.com/riccardopinato/Notes-Ecosistema/issues/51), [#60](https://github.com/riccardopinato/Notes-Ecosistema/issues/60) e [#64](https://github.com/riccardopinato/Notes-Ecosistema/issues/64) restano distinte dai gate di stabilizzazione: un MVP merged non equivale a CAP completa.

## 2. Rilievi ordinati per rischio

### P0 / **STOP RELEASE** — certificati APK release diversi fra build

Issue [#71](https://github.com/riccardopinato/Notes-Ecosistema/issues/71).

**Prova diretta:** APK ARM64 `0.56.3` da [CI #42058312645](https://github.com/riccardopinato/Notes-Ecosistema/actions/runs/42058312645) e da [CI #42060940945](https://github.com/riccardopinato/Notes-Ecosistema/actions/runs/42060940945), 39.442.239 byte ciascuno. Esame della firma APK v2:

| Run | Subject | SHA-256 fingerprint del certificato |
| --- | --- | --- |
| #42058312645 | `C=US,O=Android,CN=Android Debug` | `44e1ddc93599cebb65209f39eaae4c5707b75f4a06f6e7d6b00baa0a21f5ac88` |
| #42060940945 | `C=US,O=Android,CN=Android Debug` | `02f538faf21b4aecd8f5b893a3f3738048b8cbad7f3b90e4ada309392336e41e` |

Le due APK hanno la stessa applicationId configurata in CI (`it.notes.ecosystem.lymlyc`) ma **firme non coincidenti**. Android può rifiutare un aggiornamento in-place con certificati diversi. **Non disinstallare per aggirare la firma senza un backup/restore già verificato**, perché lo storage privato può essere perso. Non esiste evidenza di un keystore di release persistente configurato nella workflow. È un gate distinto dalla semplice build verde.

**Acceptance:** keystore/gestione Play signing fuori repository e con accesso controllato; prova firma stabile su due build; incremento versionCode; installazione di aggiornamento con dati sintetici preservati; `apksigner verify --print-certs`; evidenza di firma di produzione. Non caricare mai il keystore nel repository.

### P1 — build non completamente riproducibili

Issue [#72](https://github.com/riccardopinato/Notes-Ecosistema/issues/72). `flutter_app/pubspec.yaml` usa vincoli caret, `flutter_app/pubspec.lock` non compare nella tree, `flutter-action` segue il canale `stable` senza versione Flutter fissata e `android/` viene ricreato ad ogni CI via `flutter create`. Non è un CI failure attuale, ma un rischio di drift e incompatibilità nel tempo. Stabilizzare toolchain/lock/template, verificare gli hash e versioni risolte senza cambiare le identità o i dati.

### P1 — percorsi Android reali non coperti da suite strumentale

La CI non lancia test `integration_test` su device/emulatore. I test Dart sono numerosi (inclusi 14 widget), ma i bridge Android/Kotlin/JNI/permessi, il ripristino SQLite dopo arresto forzato, la sincronizzazione multi-device e il picker file vanno provati a parte. Non inventare «0 test reali eseguiti»: **nessuna evidenza real-device in questa analisi**.

### P1 — data-safety e recovery sotto errore

I roundtrip del codec di backup, la compatibilità v1 e i rifiuti di archivi non validi sono testati nel dominio. **Non** sono una prova equivalente a un restore interrotto su Android con database, file CAS, sidecar, reminder e account/sync in uno stato reale. Prima della prima release firmata: fixture con documenti, allegati, task, Whiteboard e tombstone; kill/restart/restore; hash sorgenti e report riferimenti orfani.

### P1 — funzionalità native con certificazione separata

- Whiteboard/stylus: test automatici verdi; checklist `flutter_app/WHITEBOARD_DEVICE_QA_0_54_3.md` ancora da firmare con device.
- PDF Toolbox: feature flag off per utenti, #70 con 12/12 casi **NOT RUN**, license/NOTICE e PDF-JPX da verificare.
- AI Needle: pack da 35,3 MB on-demand, runtime nativo nella base; qualità, RAM, latenza, install/cancel/remove e comportamento senza AICore non certificabili da un parser test.

### P2 — performance, leggerezza e accessibilità

La release ARM64 esaminata è **39.442.239 byte (~37,62 MiB / 39,44 MB decimali)**. In `.github/workflows/flutter-port-ci.yml` c'è un soft target **38 MiB**, un guard-rail incidentale **80 MiB** e la verifica che `needle3.cact` non venga accidentalmente incorporato nel base APK. Il modello resta on-demand in AAB. Il target indicativo di meno di 30 MB deve essere studiato con APK Analyzer prima di rimuovere dipendenze. Aggiungere budget di apertura e RAM misurati, TalkBack e reflow prima di asserire «fluido».

## 3. Gate Step 1: stato e ordine delle azioni

| Gate | Stato al 05/11/2026 | Prossima azione |
| --- | --- | --- |
| Inventory sorgenti e test | **COMPLETATO** | Mantenere la matrice nel report; non duplicare implementazioni |
| Flutter analyze/test/build sul commit base | **PASS** | Rieseguire su ogni PR che modifica `flutter_app/**` |
| Deploy Web Preview sul commit base | **PASS** | Smoke visivo e accessibilità non dedotti dal deploy |
| Firma release persistente | **BLOCKED / P0** | #71; prima di qualsiasi APK dichiarato aggiornamento sicuro |
| Toolchain e dependency resolution | **RISK / P1** | #72 |
| Restore fisico/aggiornamento | **NOT VERIFIED** | Step 2 + hardware QA; nessun dato vero nei test |
| Whiteboard hardware | **NOT VERIFIED** | `WHITEBOARD_DEVICE_QA_0_54_3.md` |
| PDF Toolbox hardware | **NOT RUN** | #70; feature off |
| AI locale hardware | **NOT VERIFIED** | ARM64 + opzionale pack; metriche e fallback |
| Play release e monetizzazione | **NOT CERTIFIED** | Firma, privacy/licenze, Play Console e test interni separati |

### Sequenza consigliata (nessun intervento eseguito in questa PR di audit)

1. **P0**: inventario della firma delle installazioni esistenti, signing pipeline sicura e QA aggiornamento senza perdita dati (#71).
2. **P1**: backup/restore atomico da fixture multi-entità e scenari crash/rollback reali; integrare regressioni deterministiche in CI.
3. **P1**: pin di Flutter/Dart, lockfile, Android build toolchain e dipendenze risolte (#72).
4. **P1**: smoke Android con PDF originali sintetici, Whiteboard/stylus, AI/pack, reti intermittenti e autorizzazioni; registrare evidenza senza dati personali.
5. **P2**: benchmark 500/5000 note, traccia tempi/RAM/jank e budget APK; ottimizzare solo hot spot misurati.
6. Infine aggiornare #60/roadmap, poi eventualmente aprire una release candidate. Non dichiarare DEVICE_VERIFIED o RELEASE senza prove.

## 4. Regole di sicurezza per la prosecuzione

- **Branch e PR isolati** per ciascun gruppo di riparazioni; nessuna riscrittura dell'architettura funzionale, nessuna seconda source of truth per note/task.
- Nessun token/keystore/password nei file, artifact o log CI. Le chiavi devono essere fornite dal proprietario tramite GitHub Actions secrets o configurazione Play.
- Non forzare l'installazione di un APK incompatibile via disinstallazione automatica; non mettere a rischio dati reali.
- Testare con documenti, note, account e PDF **sintetici**; registrare device/OS/versionCode/fingerprint/SHA e PASS/FAIL.
- `CI PASS` ≠ `DEVICE PASS` ≠ `RELEASE READY`; mantenere questi stati disgiunti.
- Questa PR crea **soltanto evidenza di audit**: non modifica l'app, le dipendenze, l'identità Android o le capability.
