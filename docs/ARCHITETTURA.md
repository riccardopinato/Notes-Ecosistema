# Stato architetturale corrente — 0.25.0

Whiteboard e Mind Map riusano NoteEntity + SketchInfo tipizzato (`SKETCH` / `WHITEBOARD`) senza nuova migrazione Room. Il body resta il payload visuale canonico; Universal Blocks collega le lavagne tramite `notes-board://UUID`. Room resta v8.

# Stato architetturale corrente — 0.24.1

Baseline performance consolidata: Room v8, R8/shrink attivi, hot path testati e Sketch persistence debounced/off-main.

# Stato architetturale corrente — 0.23.0

## Planner Pro

```
TaskDetails
    ├── due                  -> scadenza
    ├── plannedDate          -> giorno di lavoro
    ├── plannedTime          -> slot opzionale
    └── plannedMinutes       -> durata

PlannerScreen
    ├── Agenda
    ├── Day
    ├── Week
    └── Month
          ↓
PlannerPro (pure domain)
          ↓
TaskCodec
          ↓
NoteEntity.taskJson
```

Specifiche architetturali:
- nessuna tabella Calendar;
- nessuna migrazione Room: Room resta v8;
- time blocking vive nel taskJson;
- Google/Apple Calendar NON sono sorgente dati in 0.23;
- possibile integrazione calendario esterno futura tramite adapter.

# Stato architetturale corrente — 0.22.0

## Smart Capture

```
ExternalCapture
    ↓
CaptureActivity
    ↓
SmartCaptureViewModel
    ├── AttachmentFiles
    ├── OcrEngine
    └── WebCapture
         ↓
EditorViewModel
         ↓
notes.body + notes-asset://
```

- URI Android non entrano nel dominio persistente.
- Gli URI vengono consumati, copiati nello store SHA-256 e poi il body contiene solo `notes-asset://`.
- OCR non genera nuovi record Room.
- Web Snapshot è Markdown.
- Document Scanner non cambia il modello dati.
- Room resta v8: nessuna nuova migrazione.

# Stato architetturale corrente — 0.21.0

- Sketchbook Pro: supporto multi-pagina (fino a 64 pagine), modelli carta (bianca, righe, quadretti, puntini, cornell), forme vettoriali, testo, strumento lasso e pressione stylus.
- Integrazione bidirezionale con Universal Block Editor tramite il blocco `DRAWING` e schema `notes-sketch://<sketchId>`.
- Retrocompatibilità totale con formati sketch v1 e sync GitHub v6.

# Stato architetturale corrente — 0.20.0

- Room resta schema v8: nessuna nuova migrazione rispetto alla 0.19.
- È disponibile il primo Universal Block Editor tramite la modalità `Blocchi` nell'editor nota.
- `notes.body` resta il formato canonico/portabile per backup, ricerca, cronologia, template e GitHub Sync.
- `content_blocks` conserva la rappresentazione strutturata delle note che hanno usato il Block Editor.
- In caso di divergenza tra `content_blocks` e `notes.body`, prevale sempre `notes.body` e i blocchi vengono rigenerati.
- Il Block Editor supporta: testo, Markdown libero, heading H1-H3, checklist, quote, code block, callout, divider, trasformazione tipo, duplicazione, eliminazione e riordino.
- Gli allegati IMAGE/AUDIO/FILE restano nel formato Markdown `notes-asset://` e vengono preservati senza conversioni proprietarie.
- L'editor Markdown, la modalità Checklist e l'Anteprima continuano a funzionare come prima.
- Whiteboard, database/objects, OCR e block multimedia visuale avanzato restano step successivi.

# Stato architetturale corrente — 0.19.0

- Room schema v8.
- `notes.body` resta la fonte canonica dell'editor Markdown legacy.
- `content_blocks` è stato introdotto come fondazione non distruttiva per il futuro Universal Block Editor.
- Nessuna migrazione massiva viene eseguita: `ContentBlockStore.ensureLegacyMarkdown(noteId)` crea il bridge solo su richiesta.
- Task (`taskJson`) e Sketch (`sketchJson`) restano invariati nella 0.19.
- Backup e GitHub Sync restano sul formato 0.18 finché il block editor non diventa canonico.

# Architettura attuale 0.9

Room v4 aggiunge pinned/archived con default false e catena completa di migrazioni. Backup v2 e sincronizzazione v2 includono i nuovi flag; lettori compatibili con v1. MarkdownEditing opera su selezioni e MarkdownPreview usa Markwon su dispatcher Default. Dettagli e limiti in AGGIORNAMENTO_090.md. La descrizione seguente riguarda la base precedente.

# Architettura 0.7

Kotlin/Compose, Room, Flow e DataStore della v0.5 mantenuti. Nessun codice degli APK
analizzati è stato copiato. Moduli nuovi implementati specificamente per Notes.

## GitHub
SyncDocument/SyncCodec definiscono il formato; SyncEngine contiene confronto e
checkpoint, testato su JVM con trasporto simulato. GitHubApi usa HTTPS verso
api.github.com con timeout, limiti, SHA atteso, niente redirect con credenziali.
SyncStorage conserva credenziali cifrate e checkpoint locali tramite AtomicFile.
GitHubSync serializza collegamento, worker e risoluzioni; WorkManager gestisce lavoro
persistente vincolato alla rete. I cambiamenti salvati in Room fungono da coda durabile:
si confrontano con il checkpoint anche dopo un riavvio. Note aperte sono contate per ID.

## Cronologia
Room v3 aggiunge note_revisions e indice noteId con MIGRATION_2_3. Le vecchie migrazioni
restano registrate. Ogni salvataggio conserva il contenuto precedente nella stessa
transazione e mantiene le 50 versioni più recenti. La query di deduplicazione legge
solo l'ultima revisione. Cronologia del contenuto (titolo, corpo, raccolta), non registro
di ogni cambiamento ai preferiti. Nessuna retroattività: comincia dall'aggiornamento.
Ripristino in bozza solo con editor senza modifiche pendenti; occorre Salva per applicare.
La cronologia è locale e non entra nel backup JSON v1: comunicarlo in UI e documentazione.

## Checklist
Rappresentazione Markdown invariata. Indentazione di 2/3 spazi dopo un'attività indica
una sottoattività; 4 spazi restano codice e vengono ignorati. Un livello supportato.
Le operazioni usano snapshot esatto del corpo e indici di riga ricalcolati: non sono
ID persistenti di attività e non introducono ancora promemoria per singola sottoattività.
Spostare un genitore sposta i figli, senza attraversare prosa o blocchi di codice.
Le azioni sono eseguite su Default, con ricontrollo del testo prima di aggiornare la bozza.
Completate in fondo riordina stabilmente ciascuna sezione e mantiene la gerarchia.
Le spunte dei genitori non completano automaticamente i figli.
La duplicazione crea un nuovo UUID della nota, includendo testo e checklist.

## Build
versionName 0.7.0, versionCode 7. WorkManager 2.11.2 e org.json per test JVM aggiunti.
Schema Room 3.json deve essere generato dalla build KSP e conservato dopo verifica;
non è stato inventato un identityHash. I file schema 1/2 restano invariati.
