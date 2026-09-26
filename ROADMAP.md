# Notes Ecosistema — Roadmap

## Stato corrente

- Versione: **0.37.0+47**
- Stack attivo: Flutter + SQLite/sqflite
- Baseline dati: compatibilità schema Room v8
- Strategia: local-first, private-by-default, REUSE-FIRST
- Validazione: FAST / FULL / CERTIFIED
- Roadmap riconciliata P0–P5: **P0–P4 completati; P5 implementato, gate FULL in validazione**
- UI polish 0.36.1: contrasto light theme corretto, dark theme preservato.
- Gate FULL v0.37: obbligatorio sull'head finale prima del merge

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

**Implementato in 0.37.0 — merge subordinato al gate FULL**

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

La roadmap P0–P5 è **funzionalmente implementata** con la v0.37; P5 diventa completato solo dopo il gate FULL dell'head finale.

Il merge della release finale è consentito solo da un head che supera il gate FULL corrente:

- Dart format;
- Flutter analyze;
- suite test completa, inclusi i test calendario locale-aware;
- APK debug;
- APK release split-per-ABI;
- R8/resource shrinking;
- size gate;
- Evidence Bundle;
- SHA-256 dell'artefatto release.

L'hash e la dimensione dell'APK appartengono all'Evidence Bundle generato dall'esatto head validato e non vengono hardcodati qui, per evitare documentazione stale dopo commit successivi.

La chiusura funzionale della roadmap **non equivale** alla certificazione hardware. Il verdetto CERTIFIED richiede inoltre i test real-device previsti dal Master Prompt corrente per le funzioni native critiche.

## Principi permanenti

- REUSE-FIRST: estendere i sistemi canonici, non crearne duplicati.
- CORE APP != AI.
- Originale immutabile; elaborazioni come derivati eliminabili/rigenerabili.
- Anti-lock-in: formati portabili, backup completo dei sidecar e dati esportabili.
- Graceful degradation: ridurre elaborazioni costose prima di compromettere editing o salvataggio.
- Shared Spaces è il workspace collaborativo canonico.
- README e ROADMAP vanno aggiornati a ogni release/step completato.
