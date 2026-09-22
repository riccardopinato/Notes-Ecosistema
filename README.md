# Notes — Ecosistema 0.25.0
## Whiteboard & Mind Map 0.25

- Whiteboard local-first integrata nello stesso contenitore NoteEntity dello Sketchbook.
- Canvas infinito con pan/zoom, griglia, sticky, testo, penna, evidenziatore, gomma e forme.
- Collegamenti tra nodi e collegamenti a note/task esistenti.
- Modalità Mind Map con nodi figli e auto-layout.
- Undo/redo e autosave debounced con serializzazione off-main.
- Nuovi blocchi WHITEBOARD nel Universal Block Editor tramite `notes-board://UUID`.
- Libreria distingue Disegni e Lavagne senza cambiare Room: resta v8.
- Routing Sketch/Whiteboard separato e metadati visuali retrocompatibili.


## Performance & Smoothness 0.24 / 0.24.1

- Redmi Note 10 Pro usato come device minimo di riferimento.
- Autosave delle bozze debounced/coalesced.
- Universal Block Editor con input bufferizzato.
- Nessun reparse completo dei blocchi a ogni carattere Markdown.
- Ricerca live con debounce breve.
- Fast-path per il badge checklist.
- Planner Pro indicizzato.
- Sketch Canvas con cache di path, pressione e carta.
- Rendering Sketch sincronizzato al frame.
- Persistenza Sketch debounced.
- Serializzazione Sketch fuori dal main thread.
- Flush finale sicuro alla chiusura dello Sketchbook.
- Smart Capture aggiornato senza bloccare le modifiche interne.
- Release R8 e resource shrinking abilitati.
- Room resta v8.


Planner Pro, calendario personale, time blocking avanzato e hardening di Smart Capture 0.22. Dettagli in `docs/ARCHITETTURA.md`.

## Planner Pro 0.23

- Agenda, Giorno, Settimana e Mese.
- Data selezionabile e navigazione periodo.
- Scadenza e pianificazione separate.
- Time blocking con ora e durata.
- Attività pianificate senza ora.
- Coda "Da pianificare".
- Warning di sovrapposizione.
- Focus avviabile dal time block.
- Durata Focus proposta dal blocco.
- Ricorrenze: nuova scadenza ma time block precedente liberato.
- Hardening Smart Capture 0.22.
- Room resta v8.

## Smart Capture 0.22

- Share Android: testo, URL, immagini e PDF.
- Share multiplo per immagini/PDF.
- Scanner documenti ML Kit con JPEG/PDF multipagina.
- OCR locale delle immagini.
- OCR automatico opzionale sugli elementi condivisi/scansionati.
- Estrazione OCR dalle immagini già allegate a una nota.
- Web Capture testuale: titolo, descrizione, fonte e testo leggibile.
- Nuovo pannello Acquisisci nell'editor.
- Nessuna modifica allo schema Room: database v8.
- notes.body resta il formato canonico/portabile.

## Resoconti storici

# Notes — Ecosistema 0.21.0

Sketchbook Pro con supporto multi-pagina, modelli di carta (righe, quadretti, puntini, cornell), forme geometriche, testi, strumento lasso e integrazione completa con l'Universal Block Editor. Dettagli in `docs/SKETCHBOOK_0210.md` e `docs/ARCHITETTURA.md`.

# Notes — Ecosistema 0.20.0

Multimedia: foto e immagini, audio registrato/importato, documenti, backup ZIP completo e allegati su GitHub. Funzioni, limiti e collaudo reale in `docs/MULTIMEDIA_0170.md`.

Verifica locale: 299 test Kotlin/JUnit superati. Nei sorgenti 307 test JVM complessivi; build Android, 8 nuovi androidTest e prove fisiche ancora da eseguire. Room 7 e protocollo note/backup JSON v6 invariati. Pacchetto ZIP multimediale separato, versione 1.

# Notes — Ecosistema 0.16.0

Ricerche salvate locali (fino a 30), ordinamento persistente, conteggi e gestione raccolte. Dettagli, limiti e collaudo: `docs/ORGANIZZAZIONE_0160.md`. Room 7 e backup/GitHub v6 conservati.

## Storico delle versioni

I resoconti seguenti sono storici. Per lo stato attuale vedere ORGANIZZAZIONE_0160.md.

### Notes — Ecosistema 0.15.0

Produttività: Kanban e stati, promemoria/rinvio, Focus con pause e intervalli, storico datato e riepilogo settimanale. Room7 invariato, backup/GitHub v6. Dettagli e limiti in docs/PRODUTTIVITA_0150.md.

227 test Kotlin locali superati; compilazione Android e prove su dispositivo ancora da eseguire per questa versione.

# Notes — Ecosistema 0.14.2

Ricerca durante la digitazione con risultati animati. Include la Cerca unificata 0.14.1. Dettagli in docs/RICERCA_LIVE_0142.md.

# Notes — Ecosistema 0.14.1

Cerca unificata: campo unico e filtri raccolti in un pannello. Dettagli e verifiche in docs/CERCA_0141.md.

# Aggiornamento corrente: Notes — Ecosistema 0.14.0

VersionCode 16. Collegamenti tra note, backlink, quattro modelli, diario giornaliero, indice Markdown e ricerca/sostituzione. Room 7 e backup/GitHub v5 conservati. Dettagli, verifiche reali e limiti in docs/AGGIORNAMENTO_0140.md.
197 test Kotlin locali superati. Build Android e collaudo dispositivo da eseguire sul progetto AI Studio; non confondere la verifica JVM con la build APK.

---

# Notes — Ecosistema 0.13.0

Sketchbook vettoriale modificabile con autosalvataggio, penna/evidenziatore/gomma, zoom, annulla/ripeti, collegamenti e PNG. Home agenda, libreria elenco/griglia, attività raggruppate, Focus dedicato ed editor Solo pagina.

VersionCode 15, Room 7 con migrazione additiva 6→7, backup/GitHub v5 con lettura dei precedenti formati. Aggiornare tutti i client sync a 0.13. Nessuna nuova dipendenza.

170 test Kotlin locali superati e migrazione SQL verificata. Build Android, suite Gradle completa, test su dispositivo e GitHub reale da eseguire. Specifica, limiti e collaudo: docs/AGGIORNAMENTO_0130.md.