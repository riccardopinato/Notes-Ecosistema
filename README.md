# Notes — Ecosistema 0.36.0

Notes Ecosistema è un workspace **Flutter, local-first e private-by-default** per note, attività, pianificazione, knowledge management, cattura rapida e collaborazione selettiva.

La linea Kotlin 0.25 è congelata nella branch `kotlin-legacy-0.25`. Lo sviluppo attivo è in `flutter_app/`.

## Stato corrente

- Versione Flutter: **0.36.0+45**
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
- Backup JSON v6 compatibile con la linea Kotlin e backup ZIP v2 completo con allegati, Universal Properties, Research/Relations/Synced Blocks e derivati; lettura retrocompatibile ZIP v1.
- Export/condivisione PNG per Sketch e Whiteboard.

## 0.36 — Optional Intelligence

- Knowledge Search locale e citabile su note personali, senza provider obbligatorio;
- note correlate determinate localmente con ranking trasparente;
- “Chiedi alle mie note” restituisce fonti/esatti documenti, non risposte inventate;
- modello **Originale → Derivato** in `notes-derivatives.db`;
- trascrizione grezza conservata separatamente;
- pulizia transcript, riassunto estrattivo e task extraction deterministici;
- ogni derivato può essere eliminato o rigenerato senza modificare audio/testo originale;
- i derivati vengono creati solo da una nota già salvata, mai da testo dirty poi scartabile;
- backup completo v2 include `notes-metadata.db`, `notes-knowledge.db` e `notes-derivatives.db` in forma portabile/remappabile;
- lifecycle purge elimina i derivati collegati alla nota;
- nessuna funzione core richiede AI, rete o account.

Dettagli: `flutter_app/OPTIONAL_INTELLIGENCE_0_36.md`.

## 0.35 — Interoperability & Research

- export/import workspace Markdown in file `.md` portabili, con tag/task preservati e Synced Blocks materializzati;
- cartella Markdown mirror selezionabile dall'utente con manifest locale, percorsi confinati e merge a tre vie;
- il manifest viene finalizzato solo dopo il commit SQLite e non autorizza overwrite quando la base manca;
- contenuti Shared Spaces read-only sono esclusi dal mirror;
- modifiche esterne non sovrascrivono mai testo locale dirty: i conflitti preservano entrambe le versioni;
- Research Workspace per fonti, URL, autore, estratti e footnote Markdown;
- relazioni note↔note persistenti e rollup deterministici;
- Synced Blocks canonici in sidecar: lo stesso blocco può essere inserito in più note e aggiornato in un punto;
- purge lifecycle rimuove fonti e relazioni della nota;
- metadati P3 in `notes-knowledge.db`, separati da `notes.db` v8.

Dettagli: `flutter_app/INTEROPERABILITY_RESEARCH_0_35.md`.

## 0.34 — Daily Work & Capture

- Home promossa a **Daily Work Briefing / Oggi**, vista deterministica e non nuova entità;
- calendario locale-aware centralizzato, default italiano/europeo Monday-first **L M M G V S D**;
- aggregazione di blocchi pianificati, task in scadenza, arretrati e novità Shared Spaces;
- Inbox/Triage: le note senza raccolta emergono nel briefing e si smistano usando raccolte/tag già esistenti;
- Quick Switcher globale per note, attività, raccolte e comandi;
- sotto-attività backward-compatible dentro `TaskDetails`;
- Focus editor: nasconde controlli secondari senza creare un editor parallelo;
- Nota vocale: avvia la registrazione già esistente e conserva l'audio originale come allegato source-of-truth;
- nessuna funzione P2 dipende dall'AI.

Dettagli: `flutter_app/DAILY_WORK_CAPTURE_0_34.md`.

## 0.33 — Universal Properties + Adaptive Editor

- proprietà universali tipizzate: testo, numero, data, select, multi-select, checkbox e stato;
- definizioni riutilizzabili a livello workspace;
- valori persistiti in un database SQLite sidecar `notes-metadata.db`, senza alterare `notes.db` v8;
- purge lifecycle integrato: l'eliminazione definitiva rimuove anche i valori sidecar;
- editor adattivo con livelli Completo, Leggero ed Essenziale;
- sui documenti grandi il parsing live dei blocchi e i knowledge tools live vengono sospesi prima di compromettere fluidità o salvataggio;
- il Markdown resta sempre la sorgente canonica del contenuto; i `content_blocks` restano derivati ricostruibili.

Dettagli: `flutter_app/PROPERTIES_ADAPTIVE_0_33.md`.

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
- backup ZIP v2 con allegati + sidecar e restore con remapping ID; decoder retrocompatibile v1;
- allegati con chiavi SHA-256;
- Shared Space bundle portabile come fallback;
- nessun reset distruttivo richiesto dalla 0.32.

Il rapporto di parità della migrazione Flutter resta in `flutter_app/PARITY_0_25_1.md`.

## Linea Kotlin storica

Il sorgente Kotlin precedente alla promozione Flutter è preservato in:

`kotlin-legacy-0.25`

Non usare quella branch per nuovo sviluppo.

## Direzione successiva

Roadmap riconciliata P0–P4:

- P0 Production Truth & Data Lifecycle: completato.
- P1 Universal Properties + Adaptive Editor: completato.
- P2 Daily Work & Capture: completato.
- P3 Interoperability & Research: completato.
- P4 Optional Intelligence: completato.

Le release restano soggette ai gate FAST/FULL/CERTIFIED: roadmap funzionale completata non equivale automaticamente a certificazione hardware.
