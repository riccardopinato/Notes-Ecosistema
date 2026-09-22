# Chiusura tecnica fase GitHub / cronologia / checklist — 0.7.1

Base: esportazione AI Studio del 14/09/2026, versione 0.7.0. Aggiornamento 0.7.1, versionCode 8; schema Room v3 invariato.

## Correzioni integrate
- La chiusura dell'ultimo editor di una nota e la variazione degli ID delle bozze attivano la pianificazione sync. Digitare dentro una bozza esistente non genera richieste sync a ogni battuta.
- Un passaggio con download bloccati da editor/bozze richiede un retry WorkManager. Questo copre anche una richiesta di pianificazione accorpata mentre un worker è già in esecuzione. Android e il backoff possono ritardare il nuovo passaggio; non si promette esecuzione immediata.
- Budget di 5 MB controllato anche sull'unione dei due archivi prima dei trasferimenti, contando una volta ciascun ID e riservando la versione più grande. Anche i conflitti sono conteggiati prudenzialmente. Durante il passaggio si ricontrolla una nota modificata dopo la fotografia iniziale; restano per-file i checkpoint e l'atomicità.
- Corretto HistoryMigrationTest: lo schema storico può omettere la proprietà indices sulle tabelle senza indici. Gli schemi storici non vengono modificati.

## Verifiche realmente eseguite qui
- 46 test JVM Kotlin superati sui sorgenti della versione esportata più queste correzioni. SyncEngine 13, SyncCodec 6, Checklist 8, ChecklistEditing 10, TaskIndex 4, FilterNotes 5.
- SQLite locale: eseguite le istruzioni SQL reali della migrazione 2→3; note e bozze conservate, colonne confrontate con lo schema v3 esportato. Verificata conservazione delle ultime 50 revisioni su 60 con timestamp identico.
- Questo controllo SQLite non sostituisce il test Android Room.
- Nuovo test strumentale per il conteggio di due editor sulla stessa nota; aggiunto ma non eseguito qui.

## Registro dello step
IMPLEMENTATO E VERIFICATO JVM: motore sync, codec, operazioni checklist, correzioni del budget.
IMPLEMENTATO, VERIFICATO SQL LOCALE: migrazione e limite cronologia.
IMPLEMENTATO, DA VERIFICARE ANDROID: notifiche di chiusura editor/scarto bozza, retry WorkManager, test del repository, test Room e interfaccia.
DA ESEGUIRE: compilazione APK 0.7.1 e suite Gradle completa in AI Studio; prova GitHub reale fra due installazioni.
Lo step non va dichiarato interamente collaudato finché le ultime prove non hanno un esito registrato.

## Prova finale per archiviare lo step
1. Aggiornare una installazione v0.5 con note/bozze a 0.7.1: verificare conservazione dei dati e recupero cronologia.
2. Usare due installazioni A/B e un repository privato di prova già inizializzato. Creare da A, sincronizzare, verificare su B; modificare da B e verificare su A.
3. Su A aprire una nota; su B modificarla e sincronizzare. Su A la modifica remota resta in attesa. Chiudere l'editor senza modifiche e verificare il passaggio automatico successivo. Ripetere con bozza, poi scartarla. Usare Sincronizza ora per distinguere un ritardo del sistema da un errore del motore.
4. Modificare offline lo stesso testo su A/B, ricollegare e provare separatamente Locale, Remota, Entrambe; verificare i contenuti dopo un ulteriore passaggio su entrambi.
5. Cestinare e ripristinare, verificando propagazione; riavviare e ripetere un passaggio senza modifiche: nessun commit aggiuntivo.
6. Verificare checklist con testo intercalato, sottoattività e riordino; esportare/reimportare backup. Il backup v1 include bozze e raccolte vuote; esclude la cronologia. GitHub esclude tutti e tre.
Registrare per ogni prova PASS/FAIL/NON ESEGUITO e il dispositivo. Mai riportare token.

## Step successivo proposto
Dopo il collaudo: acquisizione rapida tramite Condividi di Android, scorciatoia Nuova nota e widget. Nessuna di queste funzioni è inclusa in questo aggiornamento correttivo.
