# Notes Ecosistema 0.47 → 0.51

Questo ciclo parte dalla baseline consolidata 0.46.0+57 e applica Rule Zero: riuso dei sistemi esistenti, nessun nuovo Core parallelo e nessun over-engineering.

## 0.47 — P2.5 Import Provenance & Idempotency

- sidecar locale `notes-imports.db` separato dal Core;
- identità esterna composta da source / sourceInstance / externalId;
- fingerprint deterministico di contenuto e metadati;
- batch import persistenti;
- decisioni: create / unchanged / update / keepLocal / conflict;
- conflitti non distruttivi: la versione esterna viene preservata come copia separata;
- il purge di una Note elimina anche la provenance che punta a quell'ID;
- Markdown import usa il motore idempotente condiviso.

## 0.48 — Unified Retrieval & Search

- ranking deterministico condiviso fra Library Search e Quick Switcher;
- la ricerca live ordina per rilevanza quando è attivo l'ordinamento recente;
- Knowledge Search indicizza lo stesso oggetto canonico attraverso:
  - Note e Task;
  - OCR e Derivatives;
  - Study;
  - annotazioni PDF;
  - Research Sources;
- più hit sidecar della stessa Note vengono collassate sullo stesso oggetto canonico;
- nessun vector DB e nessuna AI obbligatoria.

## 0.49 — Interoperability Core

- deep link stabili:
  - `notes://object/<id>`;
  - `notes://project/<id>`;
  - `notes://study/<id>`;
- copia link disponibile dalle Note;
- Android gestisce link Notes anche a cold start;
- Open-in Android per Markdown/TXT/PDF usando la pipeline capture esistente;
- nessun secondo storage o secondo importer per l'apertura file.

## 0.50 — Obsidian / Markdown Migration Pro

- import vault da ZIP;
- frontmatter compatibile: title e tags;
- campi frontmatter non mappati riportati nel lossiness report;
- wikilink risolti verso stable Notes links quando il target è riconoscibile;
- embedded image/file supportati convertiti nel CAS allegati;
- path Obsidian preservato come metadata comment non distruttivo;
- file non supportati conteggiati e non interpretati;
- lo stesso Import Provenance Engine rende i re-import idempotenti.

## 0.51 — Product & UX Polish

- NavigationRail automatica su layout >= 900 px;
- NavigationBar mantenuta su mobile;
- shortcut tastiera:
  - Ctrl+K Quick Switcher;
  - Ctrl+N nuova nota;
  - Ctrl+Shift+F ricerca;
- ricerca in Search mode con focus immediato;
- copy-link esplicito;
- Lavagna/Mind Map sempre aperta con il centro logico del canvas centrato nella viewport;
- testi impostazioni aggiornati alla semantica reale di import e cleanup.

## Vincoli mantenuti

- local-first e private-by-default;
- schema Notes Core Room v8 invariato;
- sidecar dove il dato non appartiene al Core;
- nessuna AI richiesta;
- nessun CRDT globale;
- nessun runtime Feature Pack;
- nessun nuovo renderer;
- nessuna riscrittura di Shared Spaces, Projects, Study, Documents o Visual Workspace.

## Gate

La chiusura del ciclo richiede la CI standard completa: format, analyze, test, debug APK, release APK split per ABI, size gate, Evidence Bundle e Web Preview.
