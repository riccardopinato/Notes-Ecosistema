# Interoperability & Research — Notes Ecosistema 0.35.0

## Obiettivo

La 0.35 completa P3 rendendo Notes più interoperabile e più adatta a lavoro,
studio e ricerca senza trasformare il Markdown in un formato proprietario.

## Markdown Workspace

L'export portabile produce uno ZIP con:

- un file `.md` per ogni nota/attività testuale attiva;
- front matter minimale e leggibile;
- titolo e corpo Markdown standard;
- manifest separato per round-trip.

L'import crea copie e non sovrascrive mai contenuti esistenti.

## Markdown Sync Folder

L'utente può scegliere una cartella filesystem accessibile e avviare un mirror.

Ogni nota testuale personale ha un file Markdown e il mirror mantiene un
manifest `.notes-ecosistema-sync.json`.

La sincronizzazione usa tre versioni:

`base precedente + locale corrente + file esterno`

Regole:

- solo esterno cambiato -> importa esterno;
- solo locale cambiato -> scrive locale;
- entrambi invariati -> no-op;
- entrambi cambiati -> conflitto esplicito che conserva entrambe le versioni.

Nessun testo locale dirty viene sovrascritto silenziosamente.

## Research Workspace

Ogni nota può associare fonti con:

- titolo;
- URL;
- autore;
- data/pubblicazione opzionale;
- estratto/citazione.

Le fonti possono produrre footnote Markdown navigabili. Il testo della nota
resta canonico; le fonti restano metadati sidecar.

## Relations & Rollups

Le relazioni note↔note sono persistite separatamente e hanno:

- ID;
- source;
- target;
- label;
- timestamp.

Il rollup iniziale è deterministico e conta totale/label senza introdurre
formule arbitrarie o duplicare Universal Properties.

## Synced Blocks

Un blocco sincronizzato vive una sola volta in `notes-knowledge.db`.

Nel Markdown canonico viene memorizzato solo un marker stabile:

`{{notes-synced:<uuid>}}`

Il rendering risolve il marker verso il Markdown corrente del blocco. Modificare
il blocco dal Research Workspace aggiorna quindi ogni nota che lo riferisce
senza riscrivere tutte le note.

## Persistenza

P3 usa il sidecar:

`notes-knowledge.db`

con:

- `research_sources`;
- `note_relations`;
- `synced_blocks`.

Questo evita una migrazione di `notes.db` v8.

## Lifecycle

Il purge definitivo di una nota elimina:

- fonti della nota;
- relazioni in ingresso/uscita;

oltre alle pulizie 0.32/0.33 già presenti.

I synced blocks non vengono cancellati automaticamente perché possono essere
referenziati da più note.

## Test

`test/interoperability_research_test.dart` verifica:

- export/import Markdown;
- protezione conflitti esterni;
- mirror filesystem;
- footnote;
- rollup;
- marker/resolutione synced block.

FULL continua a richiedere format, analyze, suite completa, APK debug/release,
size gate ed Evidence Bundle.
