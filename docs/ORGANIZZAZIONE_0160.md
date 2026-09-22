# Notes — Ecosistema 0.16.0 · Organizzazione

Base: export (11), versione 0.15.0. Nuova versione 0.16.0, versionCode 20.

## Funzioni e collegamenti
- Cerca mantiene un unico campo testuale e i filtri nel pannello esistente. Ricerche salvate apre un pannello con salvataggio della configurazione corrente, applicazione, rinomina ed eliminazione confermata. Fino a 30 ricerche con nome univoco, massimo 80 caratteri; query fino a 8000 caratteri. Conserva query letterale, ambito, raccolta per ID, tipo di contenuto, tag AND/OR, preferiti, fissate, presenza checklist e ordine. Le note non vengono duplicate. Una raccolta rimossa rende la ricerca non applicabile, senza ampliare silenziosamente i risultati.
- Ordinamento persistente: ultima modifica (mantiene precedenza preferiti), data creazione crescente/decrescente, titolo A–Z. Le fissate restano sempre davanti; ID come spareggio stabile. L’ordine è globale per gli elenchi della libreria e viene ripristinato applicando una ricerca salvata. Il selettore è disponibile in Note, Raccolte e Cerca. La vista elenco/griglia resta separata.
- Raccolte > Gestisci: conteggi reali per elementi attivi, archiviati, cestinati e bozze; apertura della raccolta, rinomina e rimozione delle sole raccolte vuote. I conteggi comprendono tutti gli elementi assegnati alla raccolta, incluse attività e disegni; bozze contate separatamente. Calcolo in background e in un passaggio per sorgente; indicatore testuale durante il calcolo.
- Rinomina transazionale con controllo del nome precedente e collisioni senza distinzione maiuscole/minuscole; ID invariato. Note, bozze e revisioni mantengono i loro riferimenti. Nessuna riscrittura del contenuto, nessuna modifica delle date delle note.
- Eliminazione transazionale: nuova verifica al momento della conferma, rifiuto in presenza di note anche archiviate/cestinate, bozze, editor aperti o riferimenti nella cronologia. Non cancella né sposta note. Una bozza arrivata dopo una rimozione non può salvare un riferimento orfano. La creazione raccolta chiude il dialog solo a salvataggio riuscito; errori visibili.

NotesApp richiama LibraryOrganizationBar, SavedSearchPanel e CollectionManager. NotesViewModel collega le azioni a Preferences e LocalNotesRepository. SearchControls, BulkActions, TagsEditor, ricerca dinamica e protezioni precedenti restano presenti.

## Persistenza e compatibilità
Ricerche salvate e ordine usano il Preferences DataStore già presente, con letture/scritture atomiche e confronto della ricerca attesa per rinomina/eliminazione. Sono preferenze LOCALI, escluse dal backup delle note e da GitHub: questa scelta è indicata anche nell’app. Nessun permesso, rete o dipendenza nuova.

Room resta alla versione 7: aggiunti solo metodi DAO, nessuna modifica a entità, migrazioni o schemi. Schemi storici byte per byte invariati; 5.json non viene inventato. Backup e SyncCodec restano v6. Firma, applicationId, toolchain, Manifest, promemoria, sketchbook e Focus conservati.

Il nome della raccolta è già incluso in backup e SyncDocument; GitHubSync osserva anche le raccolte. Una rinomina modifica quindi i documenti derivati delle note assegnate, e usa le protezioni/conflitti già esistenti. Il protocollo remoto identifica le raccolte per nome: sull’altro dispositivo può restare la vecchia raccolta vuota; le raccolte vuote non sono sincronizzate né eliminate a distanza. Nessuna nuova promessa di rinomina atomica dell’intero repository GitHub: la sincronizzazione resta per singolo file.

## Verifiche effettive in AI Studio
- Build APK `:app:assembleDebug` completata con successo (output `app-debug.apk`).
- Suite JVM `:app:testDebugUnitTest` eseguita con successo: 265 test completati (0 falliti, 0 errori, 0 ignorati) conteggiati dai 23 file XML di report in `app/build/test-results/testDebugUnitTest/`.
- 11 test `CollectionManagementTest` (androidTest) non eseguiti e lasciati aperti per assenza di dispositivo o emulatore ADB connesso (`adb devices` vuoto).
- Coperti ordinamenti/precedenze e spareggi, round-trip filtri, nomi duplicati, limite 30, versioni/ID non validi, Unicode, query letterali e conteggi incluse bozze/cestino. Schemi Room 7 invariati.

## Collaudo da eseguire in AI Studio
1. Applicare tutti i file completi del pacchetto senza rimuovere test o componenti, compilare APK e :app:testDebugUnitTest; conteggiare gli XML (attesi 265 test, riportare il risultato reale).
2. Aprire Cerca: digitare Casa → Casa di Anna, cambiare filtri/ordine, salvare, riavviare app e applicare la ricerca. Verificare esattamente gli stessi criteri, incluse query vuote e raccolte. Rinomina/elimina ricerca, prova nomi duplicati e limite 30.
3. Note/Raccolte: verificare fissate e ordinamenti, animazioni risultati, selezioni multiple disabilitate mentre si aggiorna la ricerca. Nessuna duplicazione del campo di ricerca.
4. Raccolte: crea/rinomina, mantieni una bozza assegnata, verifica backup e conflitto con una modifica remota. Prova rimozione raccolta vuota e rifiuti per archiviati, cestino, bozze e cronologia. Non eliminare protezioni per far passare il test.
5. Eseguire androidTest quando disponibile. Provare i pannelli in chiaro/scuro, tastiera, schermo piccolo, caratteri 1.3×/2×. Restano aperti anche collaudi notifiche/rinvio, Focus e GitHub tra due installazioni delle versioni precedenti.
6. Includere tutti i sorgenti e schemi nel prossimo export; se possibile aggiungere report XML dei test.

## Fonti tecniche
DataStore: https://developer.android.com/topic/libraries/architecture/datastore
Operazioni atomiche: https://developer.android.com/reference/androidx/datastore/core/DataStore
Testo per Gemini: https://ai.google.dev/gemini-api/docs/document-processing (Other document types).
