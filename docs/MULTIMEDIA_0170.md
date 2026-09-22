# Notes — Ecosistema 0.17.0 · Multimedia

Base verificata: export (12) di 0.16.0. Nessun sorgente mancante o alterato rispetto al pacchetto 0.16; tutti i 265 test JVM presenti. Solo il registro di collaudo riportava build e 265 test superati in AI Studio. Questi esiti non sono stati ricontati da XML nel presente ambiente.

Versione 0.17.0 / versionCode 21. Stile avorio, cobalto, terra e serif conservato.

## Funzioni realmente collegate nel codice
- Editor delle note di testo: pulsante Allegati nella riga degli strumenti; pannello compatto con selezione multipla, fotocamera esterna, registrazione, galleria allegati, ascolto, apertura, condivisione e rimozione dei collegamenti.
- Formati: JPEG, PNG, WebP, M4A, MP3, WAV, OGG, PDF, TXT, DOCX, XLSX e PPTX. PDF/Office/testo si aprono tramite le app disponibili sul dispositivo; non è incluso un nuovo motore PDF/Office interno. Nessun OCR, trascrizione, video o supporto HEIC dichiarato.
- Immagini: miniature caricate in background soltanto per le righe composte, decodifica ridotta, orientamento EXIF dove leggibile, visualizzatore a schermo intero con zoom/pan. Gli originali non vengono ricampionati per il salvataggio. Foto oltre 8 MiB rifiutate con errore.
- Audio: registrazione AAC/M4A fino a 5 minuti, permesso microfono richiesto al momento dell’uso, timer visibile, arresto prima di uscire in background. Non è una registrazione continua in background. Rotazione/ON_STOP interrompono e finalizzano la registrazione. Riproduzione singola con arresto, nessuna playlist/seeking o waveform.
- Registrazioni non collegate conservate nello spazio privato `media_pending`, riconoscibili nella stessa nota e recuperabili/condivisibili/eliminabili dal pannello. La copia temporanea viene rimossa solo dopo aver conservato la bozza con il collegamento. Un MP4 interrotto dal processo prima della finalizzazione può risultare illeggibile: il recupero non può essere garantito in tale caso. I file da recuperare non entrano in backup/sync finché non vengono collegati. Non sono eliminati dalla pulizia automatica degli allegati.
- Durante preparazione/import/registrazione, salvataggio, scarto e normali modifiche dell’editor sono protetti per non perdere l’inserimento in corso. Gli import attendono la scrittura della bozza. Le importazioni multiple possono fermarsi sul primo errore conservando gli allegati già aggiunti; non promettono atomicità dell’intera selezione di file.
- Anteprima Markdown: i collegamenti multimediali aprono il pannello allegati; le miniature sono nel pannello, non incorporate nel TextField Markdown. Le schede in libreria mostrano etichette degli allegati al posto dei lunghi indirizzi interni.

## Identità e compatibilità dei dati
File immutabili identificati da SHA-256 + estensione, memorizzati in `files/attachments`. Il testo conserva un normale collegamento Markdown `[nome](notes-asset://impronta.ext)`. Nomi originali sanificati e limitati, nessun percorso esterno inserito nello store. Il parser esclude link escapati, codice fenced/indentato e inline code. Non trasforma le immagini Markdown `![...]` in allegati automaticamente.

Duplicazione, revisioni, bozze, importazione come copie, pin/archivio e conflitti conservano i riferimenti. Duplicare note non duplica i file con la stessa chiave. Le revisioni restano locali come prima; per questo i loro file sono protetti dalla pulizia anche se la nota corrente non li usa più.

Room resta 7. L’unica aggiunta al DAO legge le revisioni a pagine per controllare i riferimenti senza caricare tutta la cronologia insieme. Nessuna entità o migrazione nuova, schemi storici byte per byte invariati, 5.json non inventato. Backup JSON e SyncCodec restano v6: i collegamenti sono parte del testo già supportato. Ricerche salvate/ordine restano preferenze locali. ApplicationId, firma, dipendenze, toolchain, allowBackup=false, widget e tile conservati. Permesso nuovo: RECORD_AUDIO; FileProvider esteso solo alle directory degli allegati e delle acquisizioni.

## Backup
Impostazioni → Backup completo ZIP include `bundle.json` v1, `backup.json` v6, tutti i file referenziati da note anche nel cestino e da bozze, più copie Markdown portabili con link relativi ai file assets. Include anche i disegni vettoriali precedenti.

L’export verifica prima tutti i file; se manca un allegato non dichiara il backup completo. Una destinazione già creata può comunque restare vuota/parziale in caso d’errore: l’interfaccia lo segnala.

Importa backup completo ZIP valida formato/versione, percorsi ammessi, voci duplicate, dimensioni compresse/espanse, contenuti JSON e impronte. Mostra l’anteprima prima di scrivere note. I file sono preparati in un’area temporanea, poi installati prima della transazione importCopies. Il database resta atomico; in caso di errore possono restare file senza riferimenti, ripulibili successivamente. Annullare l’anteprima elimina la preparazione. Nessuna estrazione di percorsi arbitrari.

Il JSON semplice conserva soltanto i collegamenti, non i binari. I vecchi ZIP Markdown si importano estraendone il JSON come prima: il nuovo comando ZIP accetta il pacchetto multimediale con manifest. Le registrazioni ancora da recuperare, revisioni locali, timer Focus attivo e preferenze locali non fanno parte del backup.

## GitHub
`AttachmentSync` avvolge il trasporto già esistente. Prima di pubblicare una nota carica/verifica i suoi allegati in `<cartella>/assets/`. I file sono immutabili: se una chiave remota contiene altro, si ferma senza sovrascriverla. Per il download usa i Git blobs, controlla dimensioni e SHA-256 e installa atomicamente. La lettura della directory assets è riutilizzata durante il passaggio, evitando una richiesta di metadati per ogni file.

Dopo il motore note controlla anche documenti provenienti dai checkpoint/cache e riferimenti delle versioni remote in conflitto. Una nota invariata può quindi recuperare un allegato mancante da remoto o ripristinare un file remoto mancante dal dispositivo. Il messaggio globale “Sincronizzazione completata” viene emesso soltanto dopo questa fase. I badge delle singole note continuano a descrivere l’allineamento del documento: lo stato globale include anche i file.

Avanzamento per file e retry WorkManager già esistente. Ripresa per file completo, non per byte/chunk: un trasferimento interrotto può ritrasmettere quel file, mentre quelli conclusi vengono verificati e riutilizzati. I documenti mantengono il compare-and-swap esistente. Il gruppo nota + tutti i file non è una singola transazione GitHub: caricare gli allegati prima evita pubblicare una nuova nota senza i suoi file, e l’app segnala eventuali file non ancora disponibili.

Aggiornare tutte le installazioni a 0.17 per trasferire i binari. Le versioni precedenti preservano i collegamenti testuali ma non trasferiscono i file. Nessuna cancellazione automatica di assets remoti, né riscrittura della storia Git. Gli allegati ereditano la visibilità del repository configurato; non sono cifrati dall’app.

## Limiti espliciti
- 20 chiavi distinte aggiungibili per nota tramite l’interfaccia; 8 MiB per singolo file non vuoto.
- 64 MiB di file unici nel backup o nell’insieme controllato durante un passaggio sync; non è un sistema per archivi multimediali illimitati.
- 500 file nello store principale e nel repository, massimo 256 MiB nello store principale locale. Lo spazio delle registrazioni in attesa e delle preparazioni temporanee è separato.
- JSON backup fino a 5 MiB; ZIP compresso/espanso fino a 80 MiB con ulteriori limiti per tipo di voce. I limiti del motore note restano 500 note, 256 KiB per documento e 5 MiB complessivi.
- Pulizia locale su conferma: soltanto file non referenziati da note, bozze o revisioni, più vecchi di 7 giorni. Nessuna eliminazione remota. Cache di acquisizioni/preparazioni abbandonate più vecchie di 7 giorni ripulita separatamente; `media_pending` non viene toccata.

## Verifiche effettive locali
299 test Kotlin/JUnit superati: 257 precedenti + 42 nuovi (32 AttachmentsTest e 10 AttachmentSyncTest). Coperti parsing e identità, deduplicazione, limiti, codice/escape, portabilità, checksum, atomicità file, file corrotti, backup completi/incompleti, percorsi ZIP, espansione e staging, conservazione dei riferimenti, file prima delle note, errori e recupero di file mancanti, cache e pulizia temporanea.

Nei sorgenti 307 test JVM complessivi (baseline 265 +42), inclusi 8 Robolectric preesistenti non eseguiti dal runner locale. Conteggio effettivo Gradle da verificare in AI Studio; nessun XML 0.17 prodotto localmente.

8 nuovi MediaRepositoryTest Android preparati, NON ESEGUITI: protezione note/bozze/revisioni durante pulizia, file orfani, import con stessi riferimenti, bundle + import copie, CAS remoto e lettura di tutte le pagine della cronologia. Query di paginazione verificata separatamente in SQLite sullo schema 7 con 35 righe. XML Manifest/FileProvider validi; schemi invariati. Controllo sintattico Kotlin eseguito: non equivale a compilazione Android.

Build APK, UI Android, fotocamera, microfono, codec audio, FileProvider su app esterne, ripresa reale GitHub e misure di fluidità NON eseguiti in questo ambiente. Nessuna prestazione o compatibilità hardware certificata.

## Collaudo richiesto in AI Studio e su dispositivo
1. Applicare ogni file completo del pacchetto; compilare APK e `:app:testDebugUnitTest`, contare XML (307 attesi), mantenere tutti i test preesistenti. Eseguire androidTest se ADB disponibile.
2. Editor: importare JPEG/PNG, registrare e ascoltare M4A, importare PDF/TXT/Office, aprire e condividere. Provare permesso negato, file vuoto/>8 MiB, 20 allegati, doppia importazione, zoom, tastiera, scuro/chiaro e caratteri ingranditi.
3. Registrazione: chiusura pannello, passaggio in background, rotazione, stop molto rapido, limite 5 minuti, salvataggio fallito e recupero nella stessa nota; verificare che non si registri in background e che le risorse native siano rilasciate.
4. Bozza/cronologia: chiudere e riaprire, salvare/scartare, duplicare, rimuovere un allegato e recuperare una revisione. La pulizia non deve cancellare alcun file ancora referenziato.
5. Backup: completo su altra installazione, annullamento anteprima, file mancante/corrotto, ZIP ostile/oversize, JSON senza binari e import ripetuto come copie.
6. GitHub privato di prova su due installazioni: salvataggio nota con file, download sulla seconda, rete interrotta/ripresa, nota invariata con file remoto rimosso, conflitto, file remoto alterato, limiti e repository pubblico secondo consenso. Non dichiarare collaudo live senza eseguirlo.
7. Includere tutti i sorgenti/schemi nel prossimo export e, se disponibili, i report XML. Non includere token, dati personali o file multimediali reali usati nel collaudo.

## Fonti tecniche
- https://docs.github.com/en/rest/git/blobs?apiVersion=2026-03-10
- https://docs.github.com/en/rest/repos/contents?apiVersion=2022-11-28
- https://developer.android.com/media/platform/mediarecorder

Codice implementato sul progetto, senza copiare repository esterni.
