# Acquisizione rapida — 0.8.0 (versionCode 9)

Base: ZIP utente remix-notes-—-ecosistema-14_09_26 (1).zip, v0.7.1. Identità applicazione, firma, toolchain e schemi Room conservati.

## Funzioni implementate
- Condividi → Notes per ACTION_SEND text/plain, testo e link con titolo opzionale da EXTRA_SUBJECT. Anteprima modificabile nell'editor completo, Salva/Resta/Scarta, raccolta e checklist disponibili.
- Ogni nuova apertura esterna genera un UUID interno. Gli ID negli extra non vengono usati, nemmeno tramite i valori predefiniti del SavedStateHandle. La sessione conserva il proprio UUID in savedInstanceState; alla ricreazione una bozza già modificata ha precedenza sul testo originariamente condiviso.
- CaptureActivity separata con launch mode standard: preserva l'editor della MainActivity sullo stack. Dopo Salva/Scarta ritorna alla schermata precedente. Non sostituisce contenuti di note esistenti.
- Il contenuto condiviso viene accodato come bozza locale, senza inviarlo a GitHub prima di Salva. Se la scrittura della bozza fallisce, il testo resta nell'editor e si può riprovare con Salva.
- Azioni rapide Nuova nota e Checklist, pubblicate al primo avvio della schermata principale attraverso ShortcutManager e indirizzate con Intent esplicito; usano il package effettivo dell'installazione.
- Widget con due pulsanti per aprire nuova nota o nuova checklist. Non crea voci segnaposto, non mostra contenuti delle note e non esegue aggiornamenti periodici. RemoteViews e PendingIntent immutabili; nessuna nuova dipendenza.
- Impostazioni: sezione Scrivi al volo con richiesta di aggiunta scorciatoia/widget. Il launcher decide il supporto e può richiedere conferma. In caso di mancato supporto sono mostrate le istruzioni manuali.
- Il widget segue il tema chiaro/scuro del sistema. L'editor continua a rispettare la preferenza tema dell'app.

## Ambito e limiti
Supportati testo semplice e URL testuali fino a 200 KiB complessivi in UTF-8, titolo massimo 8000 caratteri. Rifiuto esplicito dei contenuti troppo grandi, senza troncamento. Nessun download dei link e nessuna anteprima web. Allegati, immagini, PDF, HTML e condivisione multipla non inclusi. Ogni nuova condivisione volontaria crea una nuova bozza, anche se il testo è identico; la ricreazione della stessa sessione conserva lo stesso ID.
Widget indicativamente 4×2 celle; dimensioni esatte, ridimensionamento e scorciatoie dipendono dal launcher. Il widget apre l'editor: non permette scrittura direttamente sulla Home. La persistenza dopo arresto forzato dipende dal completamento della scrittura della bozza.

## Verifiche eseguite qui
56 test JVM Kotlin superati: 46 precedenti (sync/codec/checklist/indice/filtri) più 10 di acquisizione (URL esatti, Unicode/CRLF, titolo, input vuoto, budget UTF-8, limite combinato, soglia esatta, titolo eccessivo, NUL, azioni rapide senza contenuto fittizio).
XML analizzati correttamente e riferimenti delle nuove risorse controllati. Schemi Room storici e v3 identici byte per byte alla base utente.
Non eseguiti: build APK v0.8.0, suite Gradle completa, test Android, prova su launcher, condivisione reale, rotazione/arresto processo su dispositivo.
Aggiunti 8 test Android in due classi: CaptureIntentsTest (5), CaptureEditorTest (3). Questi verificano parser Intent e ViewModel/repository con Room in memoria; non sostituiscono una prova completa della Activity e del launcher.

## Collaudo richiesto in AI Studio / su dispositivo
1. Compilare APK e l'intera suite JVM, riportando conteggi dai report XML (non sommare categorie ambigue). Eseguire test strumentali se ADB disponibile.
2. Da browser condividere URL e titolo; da altra app testo multilinea. Verificare anteprima, assegnazione raccolta, Salva e Scarta; nessuna nota salvata prima di Salva.
3. Con editor già aperto e modificato, condividere altro testo: salvare/scartare la nuova bozza e tornare al precedente editor senza perdere modifiche.
4. Ruotare la schermata durante acquisizione, modificare testo, mettere l'app in background e ricreare il processo: stessa bozza senza duplicati o ritorno al testo originario, dopo completamento scrittura.
5. Provare input vuoto, allegati e testo oltre limite: messaggio di errore, nessuna nuova nota. Provare extra id di una nota esistente: nuova sessione separata.
6. Aprire MainActivity una volta, tenere premuta l'icona; provare Nuova nota e Checklist. Provare aggiunta dalla sezione Scrivi al volo e fallback manuale su launcher senza pin.
7. Aggiungere due widget; verificare entrambe le azioni, tema sistema chiaro/scuro, font grande, lettore schermo e ridimensionamento. Controllare che ogni apertura nuova abbia un ID diverso.
8. Salvare una nota acquisita, esportare/reimportare backup e verificare che entri nel flusso GitHub esistente. La prova GitHub reale e la migrazione su dispositivo della fase 0.7 restano aperte fino a esito reale.

## Fonti tecniche ufficiali consultate
- Ricezione e conferma dei dati condivisi: https://developer.android.com/develop/ui/compose/sharing/receive
- Widget Android: https://developer.android.com/develop/ui/views/appwidgets
- Creazione e aggiunta scorciatoie: https://developer.android.com/develop/ui/compose/system/shortcuts/creating-shortcuts

## Stato step
Codice implementato, test di dominio superati; integrazione Android da compilare/collaudare. Non archiviare come testato su dispositivo prima di registrare gli esiti sopra.
