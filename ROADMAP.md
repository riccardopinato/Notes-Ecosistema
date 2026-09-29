# Notes Ecosistema — Roadmap

## 0.55.1 — Semantic Integration & Quality

**Implementato in 0.55.1+70.**

- Quick Switcher integrato con il ranking ibrido canonico;
- ricerca globale Notes semantic-aware senza perdere filtri e scope;
- Knowledge Graph search semantic-aware per Note/Task;
- ranking centralizzato tramite `UnifiedRetrievalService.rankNoteIds`;
- lexical exact/prefix preservato come segnale forte;
- Web Preview allineata alle superfici Android;
- quality harness con Recall@K e MRR;
- regressioni semantic-only su Quick Switcher, Search e Graph.

## 0.55.0 — Local Semantic Retrieval

**Implementato in 0.55.0+69.**

- sidecar derivato `notes-semantic.db`;
- embedding locale deterministico 192D, senza rete né dipendenza da provider AI;
- indicizzazione incrementale con fingerprint;
- ranking ibrido Unified Retrieval + semantic similarity;
- related notes sulla stessa pipeline;
- fallback completo alla ricerca classica;
- lifecycle purge integrato;
- toggle utente con indice eliminabile/ricostruibile;
- Web Preview semantic-aware;
- benchmark automatici su footprint e throughput.

0.55.0 costruisce il contratto di embedding e l'indice locale. Un eventuale modello neurale on-device futuro potrà sostituire l'engine senza cambiare Unified Retrieval o le source of truth.

## 0.54.3 — Whiteboard Device QA & Polish

**Implementato in 0.54.3+68.**

- multi-select/lazo per nodi e testo;
- move group + Undo atomico;
- duplicazione, resize e snap opzionale;
- mini-map live per canvas grandi;
- toolbar contestuale per editing tablet;
- stress test automatici 20k/50k punti;
- checklist hardware dedicata per stylus, palm rejection e fluidità reale.

La release può superare il gate FULL automatico; il verdetto CERTIFIED resta subordinato ai test real-device descritti in `WHITEBOARD_DEVICE_QA_0_54_3.md`.

## 0.54.2 — Whiteboard Pro Hardening

**Implementato in 0.54.2+67.**

- canvas espandibile con centro logico stabile;
- drag zoom-correct e cumulativo di nodi e testo;
- Undo/Redo bounded;
- stylus pressure + palm rejection + controllo dito/navigazione;
- palette/spessori Digital Ink condivisi con Sketchbook;
- testo editabile/spostabile/ridimensionabile/ricolorabile;
- painter e gomma ottimizzati per lavagne grandi;
- limiti preventivi di complessità;
- test regressione su zoom, history, stylus e mappe profonde.

## 0.54.1 — Whiteboard Sketch Layer

**Implementato in 0.54.1+66.**

- Whiteboard/Mind Map con layer Digital Ink editabile condiviso con Sketchbook;
- strumenti penna, evidenziatore, gomma, linea, rettangolo, ellisse, freccia e testo;
- background bianco, righe, griglia o puntini;
- coordinate sketch solidali con la canvas e nodi/post-it mantenuti sopra l’inchiostro;
- viewport centrato sul centro logico a ogni apertura;
- pan/zoom e manipolazione nodi separati dal disegno;
- codec Whiteboard v1 esteso in modo backward-compatible con fallback griglia sui documenti legacy.

## 0.54 — Workflow Automations

**Implementato in 0.54.0+65.**

- motore locale e deterministico evento → azione;
- trigger create / update / task completed;
- filtri soggetto, tag e titolo;
- azioni bounded: tag, raccolta, pin e priorità;
- audit minimale e lifecycle-aware;
- Disaster Recovery v2 + Open Export;
- Web Preview verificabile;
- base localizzazione v14 con lingua sistema, fallback EN e override IT/EN/ES/FR/DE/PT;
- nessuna AI, rete, delete automation o background scheduler.

Dettagli: `flutter_app/WORKFLOW_AUTOMATIONS_0_54.md`.

### Prossimo asse candidato

**0.55 — Local Intelligence**, partendo da semantic retrieval/embeddings locali opzionali e misurabili; generazione solo dove porta valore concreto.

## 0.53 — Knowledge Graph

**Implementato in 0.53.0+64.**

- grafo derivato, senza nuova source of truth;
- nodi Note/Task/Project/Study/PDF;
- archi da internal link, relazioni, Projects, Study e Documents;
- ricerca, focus 1-hop/2-hop/all e filtri per relazione;
- layout deterministico bounded;
- apertura diretta della sorgente con permessi Shared Spaces preservati;
- accesso da Home e Quick Switcher;
- nessun graph DB, vector store o AI.

Dettagli: `flutter_app/KNOWLEDGE_GRAPH_0_53.md`.

### Prossimo asse candidato

**0.54 — Workflow Automations**, evento → azione locale e deterministica prima di qualunque automazione AI.

## 0.52 — Collaborative Workspace

**Implementato in 0.52.0+63.**

- riuso completo di Shared Spaces e Project Workspace;
- discussioni/commenti sincronizzati nel workspace;
- commenti merge-safe con tombstone;
- Viewer read-only sui contenuti ma abilitato alla discussione;
- cronologia locale degli inviti recenti;
- lifecycle esplicito: lascia spazio ≠ rimuovi dal dispositivo;
- Project Workspace team espone membri/commenti/ruolo;
- nessun CRDT, presence realtime, block ACL o secondo collaboration engine.

Dettagli: `flutter_app/COLLABORATIVE_WORKSPACE_0_52.md`.

### Prossimo asse candidato

**0.53 — Knowledge Graph**, come proiezione derivata di link, relazioni, Study, Documents e Projects. Nessuna nuova source of truth.

## 0.47 → 0.51 — Product Interoperability & UX Cycle

**Implementato in 0.51.0+62.**

- **0.47 / P2.5 Import Provenance & Idempotency:** provenance persistente, fingerprint, batch, re-import sicuro e conflitti espliciti.
- **0.48 Unified Retrieval & Search:** ranking comune, ricerca live a rilevanza, retrieval su Note/Task/OCR/Study/PDF/Research.
- **0.49 Interoperability Core:** stable deep link e Android Open-in per Markdown/TXT/PDF.
- **0.50 Obsidian / Markdown Migration Pro:** vault ZIP, frontmatter, wikilink, allegati e lossiness report.
- **0.51 Product & UX Polish:** responsive navigation, shortcut tastiera, focus Search e copy-link.

Dettagli: `flutter_app/ROADMAP_0_47_0_51.md`.

### Dopo 0.51

Il prossimo grande asse non parte automaticamente. I candidati restano Collaborative Workspace, Knowledge Graph, Workflow Automations e Local Intelligence; vanno promossi solo dopo audit di valore reale e Rule Zero.

## 0.46 — Consolidation & Quality Sweep

**Implementato in 0.46.0+57.**

- Universal Delete & Lifecycle audit sui domini canonici e sidecar;
- nessun nuovo lifecycle engine: mantenute le ownership già esistenti;
- attachment cleanup reso conservativo e sidecar-aware per Derivatives/OCR e PDF annotations;
- Study conserva intenzionalmente LearningItem e source snapshot dopo il purge della source;
- eliminazione progetto resta non distruttiva sui contenuti collegati;
- nessuna migration DB, AI, Feature Pack runtime o refactor architetturale preventivo.

### Roadmap successiva approvata

- **0.47 — P2.5 Import Provenance & Idempotency:** source/source-instance/external-id/fingerprint/import-batch, re-import sicuro e conflitti espliciti.
- **0.48 — Unified Retrieval & Search:** facade logica comune per FTS, metadata, relations, OCR, Study e Documents; ricerca live e ranking coerente.
- **0.49 — Interoperability Core:** stable deep link, Open-in e file association per i formati realmente supportati.
- **0.50 — Obsidian / Markdown Migration Pro:** cartelle, frontmatter, wikilink, media e lossiness report senza promettere pixel-perfect migration.
- **0.51 — Product & UX Polish:** navigazione, gerarchia, onboarding, accessibilità, keyboard/tablet/desktop e coerenza visuale.
- **Future:** Collaborative Workspace sopra Shared Spaces/Projects, Knowledge Graph derivato, automazioni evento→azione, Local Intelligence opzionale e Module Archive solo quando richiesto da scala reale.

## Roadmap red-team consolidata — P1.2 → P2.4

**Completata in 0.45.0+56.**

### P1.2 — True Disaster-Recovery Backup
- recovery bundle distinto dal Media Bundle v3;
- restore exact-ID per Core e sidecar;
- revision history e ContentBlock inclusi;
- asset CAS verificati;
- preflight di tutti i sidecar prima della modifica persistente;
- Media Bundle v3 resta invariato come migration/import-as-copy.

### P1.3 — Distributed Lifecycle Verification & Hardening
- delete vs offline edit verificato come conflitto, non last-write-wins;
- restore dopo tombstone verificato come upload esplicito;
- purge di tombstone GitHub già sincronizzato non provoca resurrection;
- Shared Live Sync conserva delete/edit concorrenti come conflitto;
- nessuna unificazione preventiva dei due sync engine.

### P1.4 — Stable Block Identity Contract
- nessun nuovo Block model;
- reconcile UBE preserva gli ID dei blocchi compatibili;
- edit del testo e inserimenti non rigenerano inutilmente gli ID;
- round-trip storage mantiene l'identità esplicita.

### P2.1 — Open Export strutturato completo
- Markdown human-readable e JSON machine-readable nello stesso pacchetto aperto;
- Properties, Knowledge, Projects, Study, Documents e media inclusi;
- revision history intenzionalmente esclusa perché appartiene al disaster-recovery backup;
- nessuna fusione fra Open Export e Backup.

### P2.2 — Study Core
- LearningItem source-linked + historical source snapshot;
- ReviewLog canonico e ReviewState derivato;
- SimpleStudyScheduler dietro contratto sostituibile;
- coda giornaliera bounded/anti-debt;
- UI Study raggiungibile dalla Home;
- niente FSRS avanzato, Exam, AI, gamification o collaboration Study.

### P2.3 — Document/PDF Workspace
- Note resta il document flow canonico;
- PDF originale resta asset CAS;
- OCR originale e OCR corretto distinti con provenance;
- annotation store locale con page/region anchors;
- ricerca bounded sul layer OCR;
- nessun nuovo Document Object duplicato.

### P2.4 — Visual Workspace evolution
- Sketchbook e Whiteboard restano sistemi separati;
- condivise soltanto primitive InkStroke/InkPoint e wire codec realmente duplicate;
- i codec legacy Sketch/Whiteboard restano distinti e retrocompatibili;
- nessuna Canvas universale, Graph View o Kanban-in-Canvas.

**Gate funzionale pre-release:** 140 test PASS, analyze pulito, build debug/release PASS, size gate PASS.

## Wave 1 — P1.1 Reference Lifecycle Foundation

**Implementato in 0.38.0+49.**

- contratto lifecycle condiviso e minimale per i reference già esistenti;
- internal links: rename/edit restano ID-stable, trash = `DELETED`, purge/missing = `SOURCE_MISSING`;
- Knowledge relations: lifecycle del target leggibile senza duplicare i backlink;
- Synced Blocks: `RESOLVED` / `SOURCE_MISSING` e supporto `STALE` per adapter version-aware, senza cambiare il marker canonico;
- Project links: proiezioni esistenti instradate attraverso il resolver comune; il purge continua a fare cleanup dei link;
- Shared Space references: trash distinto da missing; il purge continua a scollegare il contenuto prima della cancellazione definitiva;
- `AMBIGUOUS` è difensivo per contesti corrotti/duplicati e non cambia il modello dati valido;
- nessuna migration, nessun nuovo database, nessun renderer o sync engine parallelo.

Restano fuori da questo step Study, PDF citations, Canvas universale, CRDT, AI, Module Archive e importer generico.

## Stabilizzazione pre-P6 — 0.37.1+48

Completata prima dell'avvio di P6:

- audit dei bottom sheet e correzione del clipping/azioni non raggiungibili;
- infrastruttura UI condivisa per sheet scroll-safe e quasi full-height;
- Smart Capture con acquisizione diretta da fotocamera e galleria + OCR immediato;
- fallback sicuro per errori nativi del Document Scanner;
- sanitizzazione centralizzata degli errori tecnici mostrati in UI;
- regressione automatizzata per bottom sheet lunghi e PlatformException.

P6 resta **non avviata** fino alla chiusura della stabilizzazione. Il gate FULL automatizzato della v0.37.1 è ora **PASS** sul commit applicativo `3974382c32fa90d4896dbda102ca071a94b96b7f`: 111 test, analyze pulito, APK debug/release, size gate ed Evidence Bundle. Rimane solo la verifica real-device di fotocamera/OCR/Document Scanner prima della certificazione hardware.

## Stato corrente

- Versione: **0.54.3+68**
- Stack attivo: Flutter + SQLite/sqflite
- Baseline dati: compatibilità schema Room v8
- Strategia: local-first, private-by-default, REUSE-FIRST
- Validazione: FAST / FULL / CERTIFIED
- Roadmap riconciliata P0–P5: **funzionalmente completata**
- UI polish 0.36.1: contrasto light theme corretto, dark theme preservato.
- Gate FULL v0.37 P5: **PASS** sull'implementazione funzionale `17794574ca8db470a3a9501718032e885ff192f7`.

## P0 — Production Truth & Data Lifecycle

**Completato in 0.32.0**

- ciclo di vita universale: cestino, ripristino, eliminazione definitiva;
- purge transazionale di draft, revisioni e content blocks;
- protezione Shared Spaces prima del purge;
- cleanup allegati orfani;
- reminder esclusi per contenuti non attivi;
- README riallineato allo stato reale;
- Evidence Bundle CI e SHA-256 release artifact.

**Certificazione hardware ancora separata:** reminder/background/Doze/OEM e upgrade reale richiedono evidenza su dispositivo fisico.

## P1 — Universal Properties & Adaptive Editor

**Completato in 0.33.0**

- proprietà universali tipizzate;
- definizioni workspace riutilizzabili;
- valori persistiti in sidecar SQLite senza migrare notes.db v8;
- cleanup lifecycle dei metadata;
- editor adattivo Completo / Leggero / Essenziale;
- graceful degradation sui documenti grandi;
- Markdown sempre sorgente canonica.

## P2 — Daily Work & Capture

**Completato in 0.34.0**

- Daily Work Briefing / Oggi come vista aggregata, non nuova entità;
- convenzione calendario centralizzata e locale-aware, default italiano/europeo Monday-first **L M M G V S D**;
- task in scadenza, arretrati, pianificazione e novità Shared Spaces;
- Inbox/Triage;
- Quick Switcher;
- subtasks backward-compatible;
- Focus editor;
- Voice Capture con audio originale preservato;
- core completamente funzionante senza AI.

## P3 — Interoperability & Research

**Completato in 0.35.0**

- import/export workspace Markdown con tag/task preservati e Synced Blocks materializzati;
- cartella Markdown mirror interoperabile, path-confined e staged/finalized;
- protezione dirty-state, permessi Shared Spaces e merge a tre vie;
- conflitti preservati, mai sovrascritti silenziosamente;
- Research Workspace;
- fonti e footnote Markdown;
- relazioni note↔note;
- rollup deterministici;
- Synced Blocks canonici con preview ed export portabile;
- metadati in notes-knowledge.db separato;
- cleanup lifecycle di fonti e relazioni.

## P4 — Optional Intelligence

**Completato in 0.36.0**

- Knowledge Search locale con fonti;
- related notes;
- interfaccia provider-independent;
- modello Originale → Derivato;
- notes-derivatives.db separato;
- transcript grezzo preservato;
- cleanup transcript deterministico;
- summary estrattivo;
- task extraction solo da marker espliciti;
- lifecycle cleanup dei derivati;
- backup ZIP v2 include e remappa Properties, Knowledge e Derivatives;
- derivati persistibili solo da una fonte già salvata;
- nessuna dipendenza core da AI, rete o account.

## P5 — Project Workspace & Universal Work Views

**Completato in 0.37.0**

- sidecar `notes-projects.db` per metadati e link dei progetti personali;
- nessuna duplicazione di note/task: Project Workspace proietta gli oggetti canonici;
- progetti team basati su Shared Spaces, senza secondo sistema di membri/permessi/sync;
- viste universali Lista, Board, Tabella, Calendario e Timeline;
- Board sullo `stage` canonico di Planner Pro;
- creazione e aggiunta di contenuti dal progetto;
- Quick Switcher e Home integrati;
- lifecycle completo: archivio, cestino, ripristino, eliminazione definitiva;
- eliminare un progetto non elimina i contenuti;
- purge nota → cleanup link progetto;
- Media Bundle v3 con `projects.json`, retrocompatibile v1/v2;
- test dedicati per proiezioni, ricerca, lifecycle, Quick Switcher e backup.

**Scelte intenzionali P5:**
- la configurazione locale del wrapper progetto non introduce un nuovo protocollo cloud;
- nei progetti team, membership e contenuto vengono derivati dallo Shared Space;
- Document Workspace/PDF avanzato, graph/wiki, forms/dashboard e ulteriori moduli
  restano fuori da P5 salvo approvazione esplicita futura.

## Gate finale roadmap

La roadmap P0–P5 è **funzionalmente completa** con la v0.37. Il merge resta subordinato al gate FULL dell'head finale secondo il Master Prompt.

Il gate FULL della v0.37.0 è stato eseguito con esito positivo sul commit funzionale P5 `17794574ca8db470a3a9501718032e885ff192f7`:

- Dart format;
- Flutter analyze;
- suite test completa, inclusi i test calendario locale-aware;
- APK debug;
- APK release split-per-ABI;
- R8/resource shrinking;
- size gate;
- Evidence Bundle;
- SHA-256 dell'artefatto release.

Evidenza P5 validata: **108 test passati**, `flutter analyze` senza issue, APK debug generato, APK release split-per-ABI generati, ARM64 = **33.345.458 byte** su budget **39.845.888 byte**, SHA-256 ARM64 = `febcf7fe6df02d47e969697cd486bef34e4d53e9a9e3c234481b63946f67cfbe`, Evidence Bundle pubblicato dalla CI.

La chiusura funzionale della roadmap **non equivale** alla certificazione hardware. Il verdetto CERTIFIED richiede inoltre i test real-device previsti dal Master Prompt corrente per le funzioni native critiche.

## Principi permanenti

- REUSE-FIRST: estendere i sistemi canonici, non crearne duplicati.
- CORE APP != AI.
- Originale immutabile; elaborazioni come derivati eliminabili/rigenerabili.
- Anti-lock-in: formati portabili, backup completo dei sidecar e dati esportabili.
- Graceful degradation: ridurre elaborazioni costose prima di compromettere editing o salvataggio.
- Shared Spaces è il workspace collaborativo canonico.
- README e ROADMAP vanno aggiornati a ogni release/step completato.
