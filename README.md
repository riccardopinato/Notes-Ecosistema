# Notes — Ecosistema 0.52.0

Notes Ecosistema è un workspace **Flutter, local-first e private-by-default** per note, attività, pianificazione, knowledge management, cattura rapida e collaborazione selettiva.

La linea Kotlin 0.25 è congelata nella branch `kotlin-legacy-0.25`. Lo sviluppo attivo è in `flutter_app/`.

## 0.52 — Collaborative Workspace

- Shared Spaces resta il workspace collaborativo canonico;
- commenti workspace-level sincronizzati e merge-safe;
- Viewer può commentare senza modificare i contenuti;
- edit/delete commenti con tombstone contro resurrection offline;
- cronologia locale degli inviti recenti, non esposta agli altri membri;
- `Lascia spazio` distinto da `Rimuovi dal dispositivo`;
- Project Workspace team mostra membri, commenti e ruolo;
- nessun CRDT globale, chat parallela, ACL per blocco o secondo sync engine.

Dettagli: `flutter_app/COLLABORATIVE_WORKSPACE_0_52.md`.

## 0.51 — Product & UX Polish

- layout adattivo: NavigationRail su tablet/desktop, NavigationBar su mobile;
- shortcut Ctrl+K, Ctrl+N e Ctrl+Shift+F;
- ricerca live con focus immediato e ranking condiviso;
- stable link copiabili dalle Note.

## 0.50 — Obsidian / Markdown Migration Pro

- import vault Obsidian da ZIP;
- conversione di frontmatter compatibile, wikilink e allegati supportati;
- lossiness report per file/campi non mappati;
- re-import idempotente attraverso lo stesso motore P2.5.

## 0.49 — Interoperability Core

- deep link `notes://object/<id>`, `notes://project/<id>`, `notes://study/<id>`;
- Android cold-start e onNewIntent;
- Open-in per Markdown/TXT/PDF usando la pipeline capture esistente.

## 0.48 — Unified Retrieval & Search

- ranking unico per Library Search e Quick Switcher;
- Knowledge Search aggrega Note, Task, OCR/Derivatives, Study, PDF annotations e Research Sources;
- più hit sidecar vengono ricondotte alla stessa Note canonica.

## 0.47 — P2.5 Import Provenance & Idempotency

- provenance persistente in sidecar locale;
- source/sourceInstance/externalId + fingerprint + batch;
- create / unchanged / update / keep-local / conflict;
- conflitti non distruttivi;
- Markdown re-import senza duplicazioni.

Dettagli: `flutter_app/ROADMAP_0_47_0_51.md`.

## 0.46 — Consolidation & Quality Sweep

- Universal Delete & Lifecycle audit formalizzato senza introdurre un nuovo lifecycle engine;
- confermate le cascade esistenti per Properties, Knowledge/Relations, Derivatives, PDF annotations e Project links;
- Study mantiene intenzionalmente LearningItem e source snapshot quando la nota sorgente viene purgata;
- cleanup allegati reso **sidecar-aware**: un asset resta raggiungibile anche se è referenziato da OCR/Derivatives o PDF annotations e non più dal solo Markdown;
- riallineata la documentazione roadmap alla baseline corrente;
- nessun nuovo database, schema, AI, renderer o Feature Pack runtime.

Dettagli: `flutter_app/CONSOLIDATION_0_46.md`.

## 0.45 — Consolidated Integrity, Portability, Study, Documents & Visual Foundations

Roadmap P1.2 → P2.4 completata preservando il Core local-first e le source of truth esistenti.

- **P1.2 True Disaster-Recovery Backup:** nuovo recovery bundle distinto dal Media Bundle v3; preserva ID canonici, revisioni, ContentBlock, Properties, Knowledge/Relations/Synced Blocks, Derivatives, Projects, Study, Document annotations, Shared Spaces e asset CAS; restore con preflight completo prima della sostituzione dello stato locale.
- **P1.3 Distributed Lifecycle Verification & Hardening:** delete-vs-offline-edit resta conflitto preservato; restore dopo tombstone resta update esplicito; il purge di un tombstone GitHub già sincronizzato rimuove il file remoto invece di risuscitare l'oggetto; Shared Live Sync conserva il conflitto delete/edit.
- **P1.4 Stable Block Identity Contract:** il Block model non è stato riscritto; il reconcile preserva gli ID dei blocchi durante edit testuali e inserimenti, e gli ID persistono nel round-trip storage.
- **P2.1 Open Export strutturato:** aggiunto export portabile separato dal backup, con Markdown leggibile, JSON strutturato, Properties, Knowledge, Projects, Study, Document annotations e media; la revision history resta intenzionalmente esclusa.
- **P2.2 Study Core:** LearningItem source-linked con snapshot storico, ReviewLog canonico, ReviewState derivato, scheduler sostituibile e coda giornaliera anti-debt; nessuna dipendenza AI.
- **P2.3 Document/PDF Workspace:** la Note resta il documento a flusso; aggiunti OCR con provenance, correzione OCR separata, PDF page/region anchors, annotazioni e ricerca sul layer OCR.
- **P2.4 Visual Workspace evolution:** Sketchbook e Whiteboard restano superfici/codec separati; viene condivisa soltanto la primitiva Digital Ink realmente duplicata, senza introdurre una terza Canvas.

Validazione funzionale prima del bump release: **140 test**, analyze pulito, APK debug/release e size gate PASS; ARM64 **33.542.902 byte** su budget 39.845.888.

## 0.38 — P1.1 Reference Lifecycle Foundation

- introdotto un contratto condiviso e minimale per lo stato dei riferimenti esistenti: `RESOLVED`, `SOURCE_MISSING`, `DELETED`, `STALE`, `AMBIGUOUS`;
- nessuna nuova source of truth: Note, Knowledge relations, Synced Blocks, ProjectItemLink e Shared Spaces restano canonici nei rispettivi store;
- internal link basati su ID continuano a sopravvivere ai rename; una source nel cestino è distinta da una source definitivamente assente;
- relation/backlink conservano il modello attuale: le relazioni sono canoniche, i backlink restano derivati;
- Project Workspace usa il resolver comune senza cambiare `ProjectItemLink`;
- Shared Spaces distinguono contenuti nel cestino da contenuti non disponibili e li fanno riapparire dopo restore;
- Synced Blocks espongono la stessa semantica di risoluzione senza modificare il formato marker o lo storage;
- nessuna migrazione database e nessuna rigenerazione degli ID.

## Stabilizzazione 0.37.1 — UI Reliability & Smart Capture Recovery

- bottom sheet lunghi resi scrollabili e autorizzati a usare quasi tutta l'altezza utile dello schermo;
- Impostazioni e menu di creazione non tagliano più azioni su display compatti;
- Smart Capture aggiunge **Scatta e analizza** e **Importa e analizza**, con OCR immediato e allegato automatico;
- scanner documenti ML Kit inizializzato solo quando serve e con fallback leggibile se il servizio Android fallisce;
- errori nativi/PlatformException e stack trace non vengono più mostrati grezzi all'utente;
- test di regressione aggiunti per error sanitization e bottom sheet scrollabile;
- gate FULL automatizzato: **PASS** sul commit applicativo `3974382c32fa90d4896dbda102ca071a94b96b7f` — 111 test, analyze pulito, APK debug/release, size gate ed Evidence Bundle;
- APK ARM64 release: **33.411.010 byte**, entro il budget di **39.845.888 byte**; SHA-256 `36b8669a8453cef62dc8e54e579a2184e6c7ff952cb14a0f0cbd5ad8bb80c766`;
- resta da eseguire la verifica real-device di fotocamera, OCR e Document Scanner prima di considerare la correzione hardware-certificata.

## Stato corrente

- Versione Flutter: **0.52.0+63**
- Persistenza: SQLite/sqflite con compatibilità schema **Room v8**
- Android: minSdk 26
- CI: format, analyze, test, APK debug, APK release R8 split per ABI, size gate, evidence/hash artifact
- Gate FULL v0.37.0: **PASS** sull'implementazione P5; 108 test, analyze pulito, APK debug/release, size gate ed Evidence Bundle verificati.
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
- Backup JSON v6 compatibile con la linea Kotlin e backup ZIP v3 completo con allegati, Universal Properties, Research/Relations/Synced Blocks, derivati e Project Workspace; lettura retrocompatibile ZIP v1/v2.
- Export/condivisione PNG per Sketch e Whiteboard.

## 0.37 — Project Workspace & Universal Work Views

- Project Workspace local-first in `notes-projects.db`, senza duplicare note, task o Planner Pro;
- progetti personali basati su link agli oggetti canonici;
- progetti team collegabili a Shared Spaces, che resta fonte canonica per membri, ruoli e membership dei contenuti;
- cinque viste sullo stesso dataset: Lista, Board, Tabella, Calendario e Timeline;
- Board basata sullo `stage` già presente in `TaskDetails`;
- creazione di note/task dal progetto, aggiunta di contenuti esistenti, ricerca e filtro completati;
- lifecycle progetto con archivio, cestino, ripristino ed eliminazione definitiva non distruttiva sui contenuti;
- Quick Switcher e Home integrati con i progetti;
- Media Bundle v3 con `projects.json` e import con remapping degli ID nota;
- purge di una nota integrato con cleanup dei link progetto.

Dettagli: `flutter_app/PROJECT_WORKSPACE_0_37.md`.

## 0.36.1 — Light Theme Contrast Polish

- corretta la gerarchia cromatica del tema chiaro: headline editoriali in blu brand `#3559E0`;
- titoli/card text su superfici chiare riportati a `onSurface`;
- descrizioni, helper ed empty state su `onSurfaceVariant`;
- titolo di sezione nell'AppBar esplicitamente blu nel tema chiaro;
- il bianco resta riservato alle superfici blu/primary e agli elementi ad alto contrasto;
- dark theme invariato nella direzione visiva;
- aggiunti test automatici per impedire regressioni di contrasto.

Dettagli: `flutter_app/LIGHT_THEME_CONTRAST_0_36_1.md`.

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

Roadmap riconciliata P0–P5:

- P0 Production Truth & Data Lifecycle: completato.
- P1 Universal Properties + Adaptive Editor: completato.
- P2 Daily Work & Capture: completato.
- P3 Interoperability & Research: completato.
- P4 Optional Intelligence: completato.
- P5 Project Workspace & Universal Work Views: completato in 0.37.0.

Il gate **FULL** della v0.37.0 P5 è stato superato sul commit funzionale `17794574ca8db470a3a9501718032e885ff192f7`: 108 test, analyze pulito, APK debug/release, size gate ed Evidence Bundle. L'APK ARM64 release misura 33.345.458 byte, entro il budget di 38 MiB, con SHA-256 `febcf7fe6df02d47e969697cd486bef34e4d53e9a9e3c234481b63946f67cfbe`.

La certificazione **CERTIFIED** resta separata e richiede i test real-device previsti per le funzioni native critiche.
