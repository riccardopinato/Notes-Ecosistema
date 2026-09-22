# Source Vault — v0.1

Archivio delle 14 fonti recuperate dalla [conversazione originale](https://chatgpt.com/share/6aa2968d-16f0-83ed-bdb1-482746bc0364). Consultazione: 10 settembre 2026.

Le prime 11 provengono dall’elenco iniziale; AFFiNE, Memos e SilverBullet erano le aggiunte della conversazione. Le descrizioni sono sintetiche; la colonna Spunto indica una nostra direzione di studio, non un’analisi del codice completata.

| Fonte | Descrizione | Spunto per l’app | Fase | Licenza segnalata da GitHub |
|---|---|---|---|---|
| [TheCodeMonks/Notzz-App](https://github.com/TheCodeMonks/Notzz-App) | Base Android e organizzazione note | Architettura e persistenza | 1 | MIT |
| [laurent22/joplin](https://github.com/laurent22/joplin) | Note multipiattaforma e sincronizzazione | Offline, import/export e sync | 2, 7 | NOASSERTION |
| [karakeep-app/karakeep](https://github.com/karakeep-app/karakeep) | Raccolta di link, note e immagini | Capture Hub e archivio web | 4, 5 | AGPL-3.0 |
| [notable/notable](https://github.com/notable/notable) | Appunti Markdown | Esperienza editor e organizzazione | 3 | non rilevata |
| [BoostIO/BoostNote-Legacy](https://github.com/BoostIO/BoostNote-Legacy) | Repository legacy di note per sviluppatori | Snippet e note tecniche | 3, 6 | NOASSERTION |
| [codexu/note-gen](https://github.com/codexu/note-gen) | Cattura e organizzazione di note con AI | Inbox multimodale e assistenza opzionale | 4, 8 | GPL-3.0 |
| [0x7c13/Notepads](https://github.com/0x7c13/Notepads) | Editor di testo Windows | Semplicità editor e gestione documenti | 2, 3 | MIT |
| [glushchenko/fsnotes](https://github.com/glushchenko/fsnotes) | Appunti Markdown per Mac e iPhone | Flussi desktop/mobile | 3, 7 | MIT |
| [taniarascia/takenote](https://github.com/taniarascia/takenote) | App web per appunti | Navigazione e interazione editor | 1, 3 | MIT |
| [massCodeIO/massCode](https://github.com/massCodeIO/massCode) | Workspace locale per sviluppatori | Snippet e strumenti nel workspace | 6 | AGPL-3.0 |
| [standardnotes/app](https://github.com/standardnotes/app) | Note e file con cifratura end-to-end | Modello di privacy e sync | 7 | AGPL-3.0 |
| [toeverything/AFFiNE](https://github.com/toeverything/AFFiNE) | Workspace per documenti e pianificazione | Convergenza documenti e canvas | 6 | NOASSERTION |
| [usememos/memos](https://github.com/usememos/memos) | Note leggere e cattura rapida | Velocità della cattura | 4 | MIT |
| [silverbulletmd/silverbullet](https://github.com/silverbulletmd/silverbullet) | Produttività basata su Markdown e scripting | Estensibilità e automazioni | 8 | MIT |

## Stato dell’analisi

README/pagine principali consultati. Metadati pubblici recuperati tramite GitHub API e salvati in [JSON](source-vault.json). Nessun clone, audit tecnico approfondito o riuso di codice eseguito.

La licenza indicata è il metadato restituito da GitHub, non una verifica per ogni file, versione o sottoprogetto. NOASSERTION/non rilevata richiede lettura dei file pertinenti. Per ogni futuro riuso registrare commit, file, licenza e attribuzioni. Non riprendiamo automaticamente le etichette della chat precedente.

## Come aggiungere fonti

Aggiungere un record a questo archivio e al JSON: URL, motivo di interesse, fase, stato analisi, eventuale commit e file riusati. Conservare sempre il link originale; distinguere fonti consultate e implementazioni integrate.

## Prossime letture mirate

1. Notzz: struttura dei livelli e flussi di stato, confrontandoli con la Foundation originale.
2. Joplin: import/export e gestione offline per la fase 2/7.
3. Karakeep e Memos: percorso di cattura e organizzazione differita.
4. AFFiNE e SilverBullet: modello dei contenuti ed estensioni nella fase workspace.

## Fonti aggiuntive — Productivity / Canvas / Handwriting

### Super Productivity
https://github.com/super-productivity/super-productivity
Uso nel progetto:
- planner;
- time blocking;
- focus;
- task UX;
- statistiche produttività.
Classificazione: sorgente permissiva / verificare notices nel singolo riuso.

### Markor
https://github.com/gsantner/markor
Uso:
- Android offline-first;
- Markdown;
- todo;
- share intents.

### Excalidraw
https://github.com/excalidraw/excalidraw
Uso:
- futura Whiteboard;
- selection;
- shapes;
- arrows;
- serialization.

### Tasks.org
https://github.com/tasks/tasks
Uso:
- ricorrenze;
- reminder;
- task UX.
Non incorporare codice copyleft nel core proprietario senza verificare obblighi.

### Saber
https://github.com/saber-notes/saber
Uso:
- handwriting;
- pagine;
- stylus UX.
Principalmente reference/reimplementation se necessario.

### Xournal++
https://github.com/xournalpp/xournalpp
Uso:
- PDF annotation;
- handwriting;
- page model.

### tldraw
https://github.com/tldraw/tldraw
Uso:
- reference per infinite canvas.
Non incorporare SDK in produzione senza verifica licenza corrente.

### Anytype
https://github.com/anyproto/anytype-ts
Uso:
- object model;
- properties;
- local-first workspace.
Reference architetturale; verificare limiti di licenza commerciale.

