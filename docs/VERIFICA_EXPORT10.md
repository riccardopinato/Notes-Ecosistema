# Verifica export (10) e correzione v0.14.0

Versione ricevuta 0.14.0/code16. Tutti i 14 file del pacchetto v0.14 sono presenti: 13 coincidono, la documentazione aggiorna gli esiti. I sorgenti principali corrispondono al pacchetto consegnato.
L'export dichiara 181 test Gradle superati in docs/AGGIORNAMENTO_0140.md, ma non contiene XML dei risultati né APK. Non è possibile verificare direttamente quella esecuzione. Nei sorgenti ricevuti ci sono effettivamente 181 test JVM: mancano SketchTest (22) e due casi Sketch in SyncEngineTest. SketchRepositoryTest è ridotto da 9 a un diverso test.

Correzioni applicate:
- ripristino SketchTest e i due test del motore sync: 205 test JVM nei sorgenti;
- recupero dei 9 test SketchRepositoryTest conservando anche il nuovo caso export (10 casi totali);
- PlannerCodecTest: il test legacy v3 modifica davvero il codec attuale v5 (nell'export tentava la sostituzione di v4 e restava v5);
- Manifest: ripristino allowBackup=false e adjustResize per MainActivity; conservati QuickSyncTileService, risorse e FileProvider dell'export;
- PlannerMigrationTest: fixture v5 costruita dallo schema reale 4 con MIGRATION_4_5, senza inventare 5.json. Poi verifica le migrazioni 5→6→7;
- TagsMigrationTest: una revisione conserva i tag PRECEDENTI alla modifica, non quelli appena salvati. Corretta l'aspettativa.

Verifiche eseguite in AI Studio:
- `assembleDebug`: compilazione APK completata con successo (BUILD SUCCESSFUL).
- `:app:testDebugUnitTest`: 205 test superati, 0 falliti, 0 errori, 0 ignorati (conteggio reale ricavato dai 21 report XML in `app/build/test-results/testDebugUnitTest`).
- Test strumentali androidTest: aperti per esecuzione su dispositivo fisico o emulatore tramite ADB.

Verifiche locali propedeutiche: 197 test Kotlin/JUnit passati sui sorgenti corretti; fixture schema 4→5→6→7 verificata in SQLite; Manifest XML valido. Schema 7, QuickSyncTileService, risorse e FileProvider conservati. Nessuna migrazione o dipendenza nuova, nessun cambiamento di versione/firma/applicationId.

Da verificare su dispositivo: tastiera/rotazione nell'editor, sketchbook e PNG, timer Focus, backup e sincronizzazione fra due installazioni. Il pulsante rapido è conservato: nessun collaudo del suo funzionamento su dispositivo viene dichiarato qui.
