# Notes — Ecosistema 0.15.0 · Produttività

VersionCode 19. Base locale: v0.14.2 costruita sull'export (10) e sulle correzioni accettate. Pacchetto cumulativo applicabile alla v0.14 corretta, 0.14.1 o 0.14.2: include Cerca pulita e dinamica. Non è stato ricevuto un nuovo export dopo (10); le verifiche build/205 test riferite da AI Studio riguardavano la correzione v0.14, non questa versione.

## Attività e Kanban
Attività offre Agenda e Kanban. Kanban apre Tutte con quattro colonne: Da fare, In corso, In attesa, Completata. Ogni scheda usa l'attività vera: Apri attività e Sposta in. I menu sono utilizzabili senza trascinamento; drag-and-drop non implementato. Cestino permette Ripristina anche nel Kanban.
I filtri Oggi/Prossime/Completate/Cestino e ricerca continuano a delimitare il contenuto. In Tutte/Kanban vengono incluse le completate per popolare la quarta colonna; in Tutte/Agenda restano le aperte come prima. Completare una ricorrente registra il ciclo e la riporta Da fare con la prossima data futura, non crea una falsa copia permanente nella colonna completate.
Lo stato è salvato in TaskDetails.stage (TODO/DOING/WAITING); DONE deriva da completedAt, evitando doppie fonti di verità. Cambi di stato e salvataggi mantengono il confronto dell'intera nota attesa: un aggiornamento concorrente o una sessione Focus appena registrata non vengono sovrascritti.

## Promemoria e rinvio
Nell'editor attività: data/ora AAAA-MM-GG HH:mm, scorciatoia Tra 10 minuti e Nessuno; fuso esplicito. Orari inesistenti nel salto dell'ora legale rifiutati. Per l'ora ambigua autunnale si usa la prima occorrenza dell'offset secondo java.time. Promemoria passato ammesso e programmato appena possibile.
Un canale Android dedicato, permesso POST_NOTIFICATIONS da Android13 e accesso alle impostazioni gestiscono notifiche negate/disabilitate. Nessun permesso per sveglie esatte. WorkManager pianifica richieste una tantum persistenti senza vincolo di rete: riavvio/Doze/risparmio energetico possono ritardare la consegna. Non è una sveglia esatta.
Toccare la notifica apre l'attività effettiva in un nuovo percorso del planner. L'azione Rinvia 10 min invia un comando locale con confronto della scadenza attesa; notifiche vecchie non sovrascrivono un promemoria modificato, completato o cestinato. Il receiver non è esportato e usa PendingIntent immutabili. La richiesta viene affidata a WorkManager prima di chiudere il receiver.
Prima della notifica si ricontrollano esistenza, archiviazione, cestino, completamento e data. Aggiornamenti/cancellazioni eliminano i lavori e le notifiche superate; resta una possibile brevissima finestra fra l'ultima lettura e la notifica, risolta dal successivo aggiornamento osservato. Nessuna garanzia di atomicità tra database dell'app e servizio notifiche Android.
Le scadenze viaggiano in backup/GitHub (istante UTC + zona + orario originale). Ogni installazione notifica localmente; il registro delle notifiche già mostrate resta locale. Il rinvio aggiorna la scadenza condivisa, ma conserva reminderTime per non spostare l'orario dei futuri cicli ricorrenti. Completare cancella il promemoria non ricorrente oppure programma quello del ciclo successivo.
Importare copie può attivare i promemoria delle copie, anche scaduti: l'anteprima importazione avvisa quando presenti. Ripristino e importazione non copiano il registro locale delle notifiche consegnate.

## Focus
Preset 25/5 e 50/10, lavoro configurabile 1–120 minuti, pausa breve/lunga 1–60 minuti. Ogni quarto blocco di lavoro concluso propone la pausa lunga. Metti in pausa/Riprendi conservano il tempo residuo nel FocusStore con compare-and-swap; riaprire il processo recupera lo stato.
Il passaggio lavoro/pausa è esplicito: Registra e inizia pausa e Inizia prossimo Focus. Nessuna sequenza automatica di sessioni mentre l'app è chiusa. Alla fine della pausa non si registrano minuti di lavoro. Termina e registra conserva solo i secondi effettivamente trascorsi, escludendo il tempo in pausa; Scarta intervallo non registra quello corrente. Il tempo dei blocchi già registrati resta conservato.
La registrazione nella transazione Room usa l'ID sessione per evitare doppioni anche se l'app si interrompe tra salvataggio della sessione e aggiornamento del timer. Una sessione già registrata non viene aggiunta due volte. Il timer attivo resta locale e non viene sincronizzato; le sessioni registrate sono invece trasferibili.
Il conto alla rovescia usa ancora l'orologio del dispositivo: cambi manuali dell'ora possono alterarlo. Non sono stati aggiunti foreground service, sveglie o suoni di fine Focus. Le notifiche di questo step riguardano i promemoria delle attività. Al termine del timer l'utente conferma la registrazione nell'app.

## Storico e riepilogo
Il pulsante riepilogo Focus in Attività espande i dati reali degli ultimi sette giorni e apre lo storico datato per attività. Include attività archiviate, esclude cestinate; il riepilogo è globale, indipendente dai filtri correnti del planner. Copie importate o conflitti Entrambe con lo stesso ID sessione sono conteggiati una volta nel riepilogo; i totali per singola copia restano propri della copia.
Le sessioni precedenti alla v0.15 mantengono i totali ma non hanno date ricostruite artificialmente; non vengono attribuite a settimane inventate. Lo storico datato riguarda le nuove registrazioni. Limite preesistente conservato: 200 ricevute/sessioni per attività. Quando esaurito si può lavorare su una nuova attività; nessuna cancellazione automatica dello storico o delle ricevute.

## Persistenza e compatibilità
Room resta v7: i nuovi campi sono nel JSON taskJson già presente. Nessuna migrazione, libreria o schema fittizio aggiunto. Conservati applicationId, firma, toolchain e schemi 2/3/4/6/7 ricevuti; 5.json rimane assente.
TaskCodec legge i task storici con valori predefiniti sicuri: Da fare, nessun promemoria e nessuno storico datato. FocusClockCodec legge anche il vecchio timer a quattro campi. Backup e GitHub passano a v6 e leggono v1–v6; i vecchi client non devono riscrivere dati perdendo le nuove proprietà. Aggiornare TUTTE le installazioni dello stesso repository a 0.15 prima della sincronizzazione.
Importa copie conserva stage, scadenza/zona/orario promemoria e sessioni, continuando a rimappare collegamenti alle note. Le anteprime conflitto mostrano stato, promemoria e conteggio sessioni datate. In caso di modifiche concorrenti non viene inventata una fusione automatica dello storico.
Limiti GitHub precedenti invariati: 500 elementi, 256KiB per documento, 5MiB complessivi e metadati entro 32768 caratteri. Lo storico aumenta le dimensioni: titoli/tag lunghi possono raggiungere il limite metadati prima di 200 sessioni. I dati restano locali e l'errore sync è esplicito; non vengono troncati per aggirarlo.

## Verifiche eseguite
Build APK `:app:assembleDebug` completata con successo (output `app-debug.apk`).
Suite JVM `:app:testDebugUnitTest` eseguita con successo: 235 test completati, 0 failures, 0 errors, 0 skipped conteggiati dai 22 file XML in `app/build/test-results/testDebugUnitTest/`.
I 7 test strumentati `ProductivityRepositoryTest` non sono stati eseguiti per assenza di dispositivo/emulatore ADB connesso (`adb devices` vuoto).
Coperti stati/ricorrenze, pausa/ripresa e intervalli, round-trip timer storico e nuovo, sessioni idempotenti, riepiloghi/deduplicazione, fusi e ora legale, v6 backup/GitHub e conflitti. XML Manifest valido; schemi e NotesDatabase conservati su Room v7.

## Collaudo richiesto in AI Studio
Compilare APK e :app:testDebugUnitTest, contare esiti effettivi dagli XML (235 nei sorgenti), eseguire androidTest quando disponibile. Non eliminare test per ottenere una build riuscita.
- Aprire Agenda/Kanban, cambiare tutti gli stati, completare/riaprire, ricorrenze e ripristino dal cestino. Modifica concorrente con Focus deve produrre conflitto, non perdita di dati.
- Concedere/negare notifiche Android13+, disabilitare canale e riabilitarlo. Programmare una notifica, provare processo chiuso/riavvio/risparmio energetico, aprire la vera attività e rinviare. Vecchia notifica dopo cambio scadenza o completamento non deve mutare i dati.
- Timer da 1 minuto: pausa, attesa, ripresa, chiusura/riapertura, registrazione parziale/completa, doppia conferma, quattro blocchi e pausa lunga. Provare pausa attività completata/eliminata su altro dispositivo. Storico e riepilogo devono riflettere solo lavoro registrato.
- Backup/import v1–v6; due installazioni aggiornate con repository privato reale, conflitti su stage/scadenze/storico. Le notifiche sono locali per installazione.
- Cercare Casa/Casa di Anna, link/backlink, sketchbook/PNG, tag e azioni multiple; chiaro/scuro, tastiera, schermo piccolo e font grandi, accessibilità dei menu Kanban.
Nessuna schermata Android visualizzata, nessun APK compilato localmente, nessuna latenza/precisione notifiche misurata in questo ambiente. Rimangono aperti i collaudi fisici dei passi precedenti.

Fonti ufficiali consultate per la progettazione:
https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work
https://developer.android.com/develop/ui/views/notifications/notification-permission
Codice implementato nel progetto; nessuna porzione di repository esterno incorporata in questo step.
