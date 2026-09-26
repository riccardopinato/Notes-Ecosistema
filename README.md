# Notes — Ecosistema 0.32.0

Notes Ecosistema è un workspace **Flutter, local-first e private-by-default** per note, attività, pianificazione, knowledge management, cattura rapida e collaborazione selettiva.

La linea Kotlin 0.25 è congelata nella branch `kotlin-legacy-0.25`. Lo sviluppo attivo è in `flutter_app/`.

## Stato corrente

- Versione Flutter: **0.32.0+41**
- Persistenza: SQLite/sqflite con compatibilità schema **Room v8**
- Android: minSdk 26
- CI: format, analyze, test, APK debug, APK release R8 split per ABI, size gate, evidence/hash artifact
- Core: offline/local-first; account e cloud non sono requisiti del workspace personale

## Core prodotto

- Note Markdown, checklist, tag, raccolte, preferiti, pin, archivio e cestino.
- Universal Block Editor.
- Knowledge links, backlink, indice titoli e trova/sostituisci.
- Template e ricerche salvate.
- Planner Pro: Agenda, Giorno, Settimana, Mese, Kanban e Focus.
- Attività con pianificazione, priorità, ricorrenza, reminder e Pomodoro/focus history.
- Diario giornaliero.
- Sketchbook multipagina, Whiteboard e Mind Map.
- Smart Capture con scanner documenti, OCR, Web Capture, fotocamera e note vocali.
- Allegati immagini/audio/documenti content-addressed SHA-256.
- Quick Capture Android, shortcut, widget Home e share target.
- Promemoria Android con apertura e snooze.
- GitHub Sync con allegati e tile Quick Settings.
- Backup JSON v6 compatibile con la linea Kotlin e backup ZIP completo con allegati.
- Export/condivisione PNG per Sketch e Whiteboard.

## Shared Spaces

Shared Spaces è il workspace collaborativo canonico di Notes.

- condivisione opt-in: i contenuti restano privati finché non vengono condivisi esplicitamente;
- ruoli Proprietario, Editor e Viewer;
- inviti NS26 a scadenza;
- identità stabile collegata all'account GitHub autenticato;
- discovery multi-device degli spazi remoti;
- Live Sync tramite repository GitHub privato;
- merge non distruttivo e copie conflitto;
- Activity Feed, unread e badge;
- background Android via WorkManager;
- diagnostica permesso notifiche, canale e restrizioni background.

Non è editing simultaneo CRDT/WebSocket: il modello resta local-first, merge-based e resiliente.

## 0.32 — Production Truth & Data Lifecycle Hardening

La 0.32 consolida il ciclo di vita dei dati prima delle prossime espansioni funzionali.

- cestino universale anche per le attività;
- ripristino singolo e bulk;
- eliminazione definitiva solo da cestino;
- purge transazionale di draft, revisioni e content blocks;
- rimozione sicura dagli Shared Spaces prima del purge;
- blocco del purge quando l'utente non ha i permessi necessari sullo spazio;
- pulizia allegati orfani dopo eliminazione definitiva;
- reminder esclusi automaticamente per elementi cestinati, archiviati o completati;
- test dedicati agli invarianti di lifecycle;
- Evidence Bundle CI con SHA-256 dell'APK ARM64.

Dettagli: `flutter_app/LIFECYCLE_0_32.md`.

## Build

```bash
cd flutter_app
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --split-per-abi --no-pub --obfuscate --split-debug-info=build/symbols
```

La CI GitHub produce gli artifact APK e il bundle di evidenze della build.

## Validazione

Notes usa tre livelli:

- **FAST** — test incrementali durante lo sviluppo;
- **FULL** — format/analyze/test/build/smoke/size ai checkpoint;
- **CERTIFIED** — FULL + acceptance reale, device fisico per funzioni native critiche, configurazione release, Evidence Bundle e hash dell'artefatto testato.

Una build non è dichiarata stabile solo perché compila.

## Compatibilità e portabilità

- database compatibile con la linea Room v8;
- backup JSON v6;
- backup ZIP con allegati e restore verificato;
- allegati con chiavi SHA-256;
- Shared Space bundle portabile come fallback;
- nessun reset distruttivo richiesto dalla 0.32.

Il rapporto di parità della migrazione Flutter resta in `flutter_app/PARITY_0_25_1.md`.

## Linea Kotlin storica

Il sorgente Kotlin precedente alla promozione Flutter è preservato in:

`kotlin-legacy-0.25`

Non usare quella branch per nuovo sviluppo.

## Direzione successiva

Dopo la chiusura dei gate 0.32:

1. Universal Properties + Adaptive Editor foundation.
2. Daily Work Briefing / Today come aggregatore del workspace.
3. Task avanzati, Inbox/Triage e Quick Switcher.
4. Interoperabilità Markdown e Research Workspace.
5. AI opzionale sopra un core completamente funzionante senza AI.
