# Notes — Ecosistema 0.11.0 — code 13

## Funzioni consegnate
- Attività autonome con UUID stabile, titolo, descrizione, data facoltativa, quattro livelli di priorità, completamento e riapertura.
- Schermata Attività: Oggi (anche scadute), Prossime, Tutte (anche senza data), Completate e Cestino; ricerca e ordinamento per data/priorità. La Home distingue il numero delle note e conteggia anche le attività autonome pendenti.
- Collegamento facoltativo a una nota esistente, selezionata per titolo, con apertura dalla scheda dell’attività. Cestinare un’attività non cestina la nota; un collegamento non più disponibile resta riconoscibile e può essere rimosso.
- Ricorrenze giornaliere, settimanali e mensili. Completare un ciclo mantiene lo stesso ID, incrementa il contatore e sposta la data alla prossima occorrenza futura, saltando quelle scadute. Il mese usa plusMonths con riduzione all’ultimo giorno valido (31 gennaio→28 febbraio→28 marzo). Non crea copie o notifiche. La data ricorrente deve essere tra 2000 e 2200.
- Focus da 1 a 120 minuti: una sessione attiva per dispositivo, persistita separatamente dalle note e riaperta dopo navigazione o riavvio. Il conteggio usa la scadenza dell’orologio del dispositivo, non un processo che deve restare acceso. Al termine l’utente conferma Registra sessione; Scarta non aggiunge tempo. Nessun suono, notifica, servizio in foreground o allarme.
- Registrazione Focus transazionale e idempotente con ID sessione: se l’app si interrompe dopo aver registrato il tempo ma prima di chiudere il timer, ripetere la conferma non duplica il tempo. Ogni attività conserva il totale e fino a 200 ID sessione; raggiunto il limite, non si avviano nuove sessioni per quella attività. Timer in corso solo locale; tempo confermato e ID ricevute in backup e GitHub. Una sessione già scartata non viene recuperata.
- Editor attività con campi conservati in SavedState durante ricreazione; salvataggio basato sulla copia inizialmente aperta. Una modifica concorrente impedisce la sovrascrittura, conserva il testo nel dialog e consente Salva come nuova attività. La nuova copia non eredita Focus/completamenti precedenti.
- Checklist esistenti accessibili dal pulsante Checklist. Nessuna conversione automatica o estrazione delle righe in attività autonome: il collegamento riguarda l’intera nota. Le descrizioni delle attività non generano checklist duplicate.

## Persistenza e sincronizzazione
Le attività sono elementi distinti nell’interfaccia, conservati nella tabella notes con metadati tipizzati taskJson e lo stesso UUID usato dal motore sync. Non viene creata una seconda nota visibile per ogni attività. Le normali viste note escludono gli elementi attività.
Room 6: MIGRATION_5_6 aggiunge solo taskJson TEXT DEFAULT NULL. Note, raccolte, bozze, tag, archivio e cronologia restano invariati. Tutta la catena 1→2→3→4→5→6 è registrata. La cronologia precedente continua a riguardare i testi delle note: non è una cronologia delle proprietà del planner.
Gli export precedenti forniti non contengono 5.json, pur essendo dichiarato generato. Prima di sostituire il codice del database, generare e conservare lo schema 5 dal progetto corrente 0.10.1 con KSP; poi compilare la nuova versione e generare 6.json. Nessun identityHash inventato, nessun fallback distruttivo. Gli schemi 2/3/4 forniti restano identici.
Backup JSON e documenti GitHub passano a v4, leggendo v1/v2/v3/v4. Tutte le installazioni che condividono il repository devono essere aggiornate a 0.11. Le vecchie versioni rifiutano v4, evitando di perdere le proprietà nuove.
Il backup comprende attività, collegamenti, ricorrenze, completamento, Focus registrato e ID di deduplicazione. Importa copie assegna nuovi UUID e ricollega l’attività alla copia della nota; se la nota collegata manca dal backup, il collegamento viene eliminato invece di puntare a un originale non importato. I Markdown delle attività sono nella cartella attivita; per recuperare tutte le proprietà va usato backup.json.
I conflitti GitHub mostrano anche stato, data, priorità, ricorrenza, cicli e Focus. Conserva entrambe crea due elementi, ciascuno con i propri dati Focus: non è una fusione automatica dei tempi.
Restano i limiti sync complessivi di 500 elementi (note + attività + cestino), 256 KiB per documento, 5 MiB per archivio; import backup 5 MiB. Descrizione attività creata nell’app limitata a 32 KiB, titolo a 8000 caratteri. Sessioni Focus salvate nel database partecipano ai normali conflitti tra dispositivi; il timer attivo non si trasferisce su un altro dispositivo.

## Verifiche realmente eseguite qui
- 146 test Kotlin JVM passati sui sorgenti reali, inclusi 30 nuovi test su planner, Focus, codec e motore di sincronizzazione.
- 154 annotazioni @Test nei sorgenti JVM complessivi. Gli 8 test storici Robolectric non sono eseguiti dal runner locale: 154 è il conteggio atteso, non un risultato Gradle dichiarato.
- Migrazioni SQL 4→5→6 eseguite in SQLite usando lo schema 4 storico e le istruzioni di produzione: note, flag, bozze e revisioni conservati, taskJson inizialmente NULL, foreign_key_check senza errori. Questo non sostituisce Room su Android.
- Undici test strumentali nuovi: dieci repository per collegamenti/import, concorrenza, ricorrenze, Focus, cestino e sync; uno per migrazione dallo schema 4 fino a 6. Aggiunta migrazione 5→6 alle catene dei test precedenti.
- NON eseguiti qui: build Android/APK, suite Gradle completa, test strumentali, GitHub reale tra due installazioni, collaudo del timer su dispositivo. Mancano SDK/emulatore Android locali. Nessuna credenziale richiesta.

## Accettazione in AI Studio
1. Conservare/generare schema 5 prima dell’aggiornamento e schema 6 dopo. Compilare APK e intera suite Gradle; riportare numero reale dai report XML.
2. Verificare chiamata PlannerScreen da NotesApp, salvataggi verso repository, FocusStore e addFocus, oltre ai tre collegamenti TagsEditor/SearchControls/BulkActions della fase precedente.
3. Creare attività senza data, oggi, scaduta e futura; verificare tutte le viste, priorità, ricerca, modifica, copia, completamento, cestino/ripristino.
4. Collegare una nota, aprirla, esportare/importare: l’attività importata deve aprire la nota importata, non quella originale.
5. Completare ricorrenze e verificare stesso UUID, avanzamento e contatore, anche a fine mese. Provare salvataggio dopo modifica concorrente: nessuna sovrascrittura.
6. Avviare Focus da un minuto, uscire/rientrare/ricreare processo, registrare e riprovare dopo interruzione: nessun doppio conteggio. Scartare non incrementa il totale. Verificare il conflitto tra sessione attiva e attività cestinata (ripristinare prima di registrare).
7. Con ADB eseguire i test strumentali. Verificare due installazioni 0.11 con repository privato di prova e conflitti di date/Focus. Non dichiarare chiusi i collaudi precedenti solo perché la build riesce.

## Funzioni future, non comprese
Promemoria/notifiche, pausa del timer e cicli automatici lavoro/pausa, conversione delle singole righe checklist, calendario eventi, allegati e Sketch. Le sessioni Focus confermate sono disponibili come totale per attività, non come grafico giornaliero o diario di sessioni con date.
