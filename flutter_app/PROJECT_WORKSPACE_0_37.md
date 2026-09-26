# P5 — Project Workspace & Universal Work Views — 0.37.0

## Obiettivo

P5 trasforma Notes in un ambiente di lavoro a progetto senza introdurre copie
parallele di note, attività, planner o collaborazione.

Il principio è REUSE-FIRST:

- una nota resta una `Note`;
- un'attività resta una `Note` con `TaskDetails`;
- pianificazione, scadenze, priorità e stage restano quelli di Planner Pro;
- un progetto personale conserva solo i collegamenti agli oggetti canonici;
- un progetto team usa Shared Spaces come fonte canonica per membership,
  permessi e appartenenza dei contenuti.

## Persistenza

I metadati progetto vivono nel sidecar:

`notes-projects.db`

Tabelle:

- `projects`: nome, descrizione, lifecycle, vista preferita e riferimento
  opzionale allo Shared Space;
- `project_items`: soli collegamenti `projectId + noteId` per i progetti
  personali.

`notes.db` resta compatibile con lo schema Room v8.

Per i progetti collegati a uno Shared Space, `project_items` non diventa una
seconda membership: gli elementi mostrati derivano direttamente da
`SharedSpace.contentIds`.

## Universal Work Views

Lo stesso insieme di oggetti canonici può essere mostrato come:

1. Lista;
2. Board;
3. Tabella;
4. Calendario;
5. Timeline.

Le viste non duplicano dati.

### Board

Le attività riusano `TaskDetails.stage`:

- TODO → Da fare;
- DOING → In corso;
- DONE → Fatto.

Le note e gli altri documenti sono riferimenti, non attività artificiali.
Le attività già completate vengono proiettate nella colonna Fatto.

### Calendario e Timeline

Le date sono derivate da Planner Pro:

- `plannedDate/plannedTime` quando presenti;
- altrimenti `due`;
- gli elementi senza data restano visibili come “Senza data”.

La convenzione calendario resta quella centrale locale-aware, con default
italiano/europeo Monday-first.

## Project Workspace

La schermata Progetti offre:

- elenco progetti attivi;
- archivio;
- cestino;
- creazione progetto personale;
- creazione progetto collegato a uno Shared Space esistente;
- ricerca interna;
- filtro attività completate;
- vista preferita persistente;
- aggiunta di note, attività, disegni e lavagne esistenti;
- creazione di nuove note e attività direttamente dal progetto;
- cambio stage delle attività dalla Board;
- apertura dell'oggetto nell'editor/Planner canonico.

Per non sovraccaricare la NavigationBar mobile, Progetti è raggiungibile da:

- Home;
- Quick Switcher.

## Collaborazione

Shared Spaces resta il sistema collaborativo canonico.

Un progetto team:

- usa Owner / Editor / Viewer già esistenti;
- è read-only per Viewer;
- deriva i contenuti direttamente dallo Shared Space;
- usa Live Sync già esistente;
- non introduce CRDT, WebSocket o un secondo protocollo di sync.

Rimuovere un elemento da un progetto team significa rimuoverlo dallo Shared
Space per tutti, con conferma esplicita. L'oggetto originale non viene
eliminato.

Il nome/descrizione del wrapper Project Workspace e la vista preferita sono
metadati locali del dispositivo. Nome, membri, ruoli e membership dei
contenuti condivisi restano invece canonici nello Shared Space.

## Lifecycle

Policy P5:

- progetto attivo → archivio oppure cestino;
- progetto nel cestino → ripristino oppure eliminazione definitiva;
- eliminazione definitiva consentita solo dal cestino;
- eliminare un progetto non elimina note, task o Shared Space;
- eliminare definitivamente una nota rimuove i suoi link dai progetti
  personali;
- nei progetti team il lifecycle dei contenuti continua a essere governato
  dalle regole Shared Spaces già esistenti.

Questo recepisce il backlog “Universal Delete & Lifecycle Audit” senza
applicare cancellazioni a cascata distruttive ai contenuti del progetto.

## Backup e portabilità

Il backup ZIP completo passa a Media Bundle v3.

Nuovo sidecar:

`projects.json`

Contiene progetti e link personali ed è importato con remapping degli ID nota.
Il decoder resta retrocompatibile con Media Bundle v1 e v2.

I progetti team conservano il riferimento allo Shared Space; i dati
collaborativi continuano a essere esportati/sincronizzati dal relativo sistema
canonico, non duplicati nel sidecar progetto.

## Performance

- il motore di proiezione lavora su riferimenti agli oggetti esistenti;
- la UI limita a 500 gli elementi materializzati contemporaneamente e invita a
  usare la ricerca sui progetti più grandi;
- il limite di persistenza è 5.000 link per progetto personale;
- nessun parsing o database duplicato viene creato per ciascuna vista.

## Test

P5 aggiunge test per:

- lifecycle progetto;
- proiezione coerente degli stessi oggetti su Lista/Board/Calendario/Timeline;
- filtro attività completate;
- ricerca progetto;
- validazione;
- Quick Switcher dei progetti;
- roundtrip del nuovo sidecar `projects.json` nel Media Bundle v3.

Il gate FULL resta:

- dart format;
- flutter analyze;
- flutter test;
- APK debug;
- APK release split per ABI con R8;
- size gate;
- Evidence Bundle + SHA-256.

La certificazione hardware resta separata dal completamento funzionale P5.
