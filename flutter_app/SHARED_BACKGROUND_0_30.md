# Background Shared Activity & Android Notifications 0.30.0

## Obiettivo

La 0.30.0 porta Shared Spaces fuori dal solo foreground: Android controlla
periodicamente la cronologia remota degli spazi e può notificare nuove attività
anche quando Notes non è aperta.

## Architettura

- nessun backend aggiuntivo;
- nessun nuovo plugin Flutter;
- WorkManager Android nativo;
- rete richiesta come constraint;
- periodic work unico con intervallo minimo Android di circa 15 minuti;
- token GitHub letto dal medesimo Android Keystore già usato dall'app;
- configurazione GitHub e identità lette dalle SharedPreferences Flutter;
- formato remoto Shared Activity v2 riutilizzato senza duplicare storage.

Il worker non apre l'app e non avvia servizi permanenti.

## Sicurezza

Prima di accettare dati remoti il worker:

1. legge il token cifrato dal Keystore;
2. verifica l'account autenticato tramite /user;
3. confronta l'id GitHub con il profilo Shared Spaces locale;
4. considera solo gli spazi in cui l'identità è membro attivo;
5. accetta solo activity log v2 e limita la lettura a 200 eventi per spazio;
6. ignora gli eventi generati dall'identità corrente.

Il token non viene copiato in SharedPreferences in chiaro.

## Notifiche

Il canale Android è:

- id: shared_space_updates
- nome: Aggiornamenti Shared Spaces
- importanza: default

Per ogni Shared Space viene prodotta al massimo una notifica aggregata per
controllo background. Se sono presenti più eventi, la notifica mostra il numero
di nuove attività e l'ultima modifica.

Il worker mantiene un timestamp last-seen per spazio. Disattivare e riattivare
Live Sync crea una nuova baseline, evitando notifiche retroattive di eventi
precedenti alla riattivazione.

## Tap sulla notifica

Il tap:

1. apre Notes;
2. seleziona la sezione Spazi;
3. esegue un Live Sync foreground;
4. apre direttamente lo Shared Space interessato;
5. lascia al normale flusso 0.29 la gestione di unread e Activity Feed.

## Limite intenzionale

La 0.30 sincronizza in background la cronologia delle attività e rileva i
cambiamenti. Il trasferimento completo di note/allegati resta affidato al Live
Sync Flutter quando l'app torna attiva.

Questo evita di duplicare in Kotlin l'intero motore di merge, gli asset e la
logica SQLite, mantenendo una sola implementazione autorevole per i contenuti.

## Compatibilità

- Shared Spaces locale v1 invariato;
- remote state v2 invariato;
- inviti NS26 invariati;
- ZIP 0.26 invariati;
- nessuna migrazione database;
- nessuna nuova dipendenza Flutter;
- Android minSdk 26 invariato.
