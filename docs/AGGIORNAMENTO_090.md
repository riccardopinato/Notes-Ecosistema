# Notes — Ecosistema 0.9.0 (versionCode 10)

Base: esportazione utente remix-notes-—-ecosistema-14_09_26 (2).zip, v0.8.0. ApplicationId, firma, icone, acquisizione e widget conservati.

## Editor Markdown
Barra con grassetto, corsivo, titolo H2, elenco puntato/numerato, citazione, codice inline/blocco e dialog link. Agisce sulla selezione oppure sulla riga corrente; senza selezione i comandi inline inseriscono un testo selezionato da sostituire. Preserva testo e terminatori CRLF. Per annullare una formattazione si può modificare il Markdown direttamente; non è un editor WYSIWYG.
Schede Scrivi, Checklist e Anteprima. Anteprima nativa TextView/Markwon 4.6.2 con parser CommonMark e supporto checklist, elaborata in background soltanto quando aperta. Colori del tema app, link http/https aperti solo al tocco. Nessuna WebView o esecuzione HTML, nessun caricamento immagini esterne. Checklist in anteprima di sola lettura: modifica dalla scheda Checklist.
Anteprima limitata a 200.000 caratteri, senza troncare/modificare la nota. Oltre tale soglia o in caso di errore il testo completo resta in Scrivi. Tabelle, LaTeX e sintassi estesa non inclusi.

## Fissaggio e archivio
Dal menu della scheda: Fissa in alto / Non fissare più, Archivia / Riporta nelle note. Indicatori visivi distinti da preferiti. Ordinamento: fissate, preferite, modifica recente, ID. Il fissaggio rimane memorizzato anche archiviando/cestinando.
Archiviate escluse da Tutte, Inbox, Preferiti, ricerca ordinaria, contatore Home e attività aggregate. Nel filtro Archivio possono essere aperte, modificate e cercate; dalla sezione Cerca selezionare Archivio. Cestino ha precedenza su archivio. Le bozze delle note archiviate restano memorizzate e si recuperano aprendo la nota dall'Archivio; non sono elencate fra le bozze ordinarie. Archiviare non cancella né completa attività.
Salvare una nota già archiviata non la riporta automaticamente nelle viste ordinarie. Riportarla nelle note ripristina anche le attività aggregate. Duplicare dall'editor crea una nuova nota ordinaria, non fissata, come le altre nuove note.

## Persistenza e compatibilità
Room v4: MIGRATION_3_4 aggiunge pinned e archived INTEGER NOT NULL DEFAULT 0. Catena completa 1→2→3→4 registrata. Schemi storici 1/2/3 conservati byte per byte; schema 4.json da generare con KSP nella build effettiva, non inventare identityHash.
I flag sono preservati da salvataggio testo, cestino/ripristino, importazione copie e scritture GitHub. Operazioni locali transazionali sotto Mutex. Le revisioni continuano a conservare il contenuto precedente, non costituiscono un registro delle variazioni di fissaggio/archivio.
Backup JSON scritto in formato v2 con entrambi i booleani obbligatori; lettore accetta v1 (flag false) e v2, rifiuta tipi errati/versioni sconosciute. Bozze/raccolte/cestino conservati. Cronologia esclusa. ZIP Markdown include backup.json completo e cartelle note/archivio; per ripristinare le proprietà importare backup.json. I vecchi client rifiutano il backup v2.
GitHub: nuove scritture in formato metadati v2; lettura v1 e v2. Tutte le note salvate, incluse archiviate/fissate/cestinate, partecipano alla sincronizzazione. Vecchi file v1 invariati possono restare tali fino alla successiva scrittura. Checkpoint vecchi leggibili; confronto a tre vie comprende i due flag. Un cambio archivio concorrente a una modifica di testo genera un conflitto, senza fusione automatica o perdita silenziosa.
Aggiornare tutte le installazioni collegate allo stesso repository a Notes 0.9 prima di riprendere le modifiche sincronizzate. I client precedenti rifiutano i file v2; questo evita che eliminino i nuovi flag. Non è supportato il downgrade dopo la migrazione Room v4.

## Verifiche realmente eseguite
82 test Kotlin JVM locali superati: MarkdownEditing 12, Organization 5, BackupFormatV2 4, SyncEngine 15, SyncCodec 9, Checklist 8, ChecklistEditing 10, TaskIndex 4, FilterNotes 5, QuickCapture 10.
I 4 test BackupFormatV2 eseguono i sorgenti reali di lettura/scrittura con org.json JVM. Non è una prova Room o della UI Android. Gli 8 test storici BackupReader/BackupWriter/ChecklistBackup con runner Robolectric non sono stati eseguiti qui: restano da eseguire nella suite Gradle completa. Il test storico BackupWriter è aggiornato alla versione 2 del formato.
SQL reale della migrazione 3→4 eseguito su SQLite locale: note, raccolte, bozze e cronologia conservate, default false e vincoli verificati. Non sostituisce la convalida Room su Android.
5 test strumentali nuovi: OrganizationRepositoryTest (4) e OrganizationMigrationTest (1), NON ESEGUITI. Aggiornate le catene di migrazione nei test storici DraftsTest e HistoryMigrationTest.
APK 0.9, anteprima grafica, test Android, GitHub reale e misure di fluidità NON ESEGUITI in questo ambiente. Nessuna dichiarazione di build Android riuscita.

## Collaudo prima di archiviare lo step
1. Build APK, generazione schema Room4 e suite Gradle completa; conteggi estratti dai report XML. Conservare gli schemi storici.
2. Migrare database v3 con note/bozze/cronologia e controllare flag false; eseguire OrganizationMigrationTest e catene storiche.
3. Fissare nota più vecchia: precede preferita più recente. Archiviare una nota con checklist/bozza: assente dalle viste ordinarie, presente nell'Archivio; recuperare, modificare e riportare nelle note senza perdere flags/testo.
4. Backup v1 importato: flag false; v2 e ZIP: proprietà preservate. Reimportazione crea copie con nuovi ID, nessuna sovrascrittura.
5. Due installazioni 0.9 con repo di prova: fissaggio/archivio, ripristino, conflitto contro modifica testo, soluzione locale/remota/entrambe; controllo bozze/editor aperti ancora attivo.
6. Selezione/cursore, Unicode, IME, testo multilinea, link, codice con backtick, alternanza schede, tema chiaro/scuro, font grande e TalkBack. Verificare che anteprima non modifichi bozza e link/immagini non aprano richieste automatiche.
7. Regressione acquisizione Condividi, widget, salvataggio/scarto e processo ricreato. Le verifiche di campo delle fasi precedenti rimangono aperte fino a esito reale.

## Dipendenze e fonti
Markwon core ed ext-tasklist 4.6.2 (coordinate verificate su Maven Central). Licenza upstream inclusa in app/src/main/assets/third-party/Markwon-LICENSE.txt.
Documentazione: https://noties.io/Markwon/docs/v4/core/getting-started.html
Configurazione rendering/link/immagini: https://noties.io/Markwon/docs/v4/core/configuration.html
Checklist: https://noties.io/Markwon/docs/v4/ext-tasklist/
