# Shared Reliability Audit 0.31.1

## Scope

Hotfix di affidabilità applicato sopra la baseline 0.31.0+39 senza cambiare
schema SQLite, formato inviti o architettura local-first.

## Compatibilità remota

La cronologia `activity` non richiede un nuovo envelope incompatibile.

- writer corrente: `space.json` version 1 + campo `activity` opzionale;
- reader corrente: accetta version 1 e la storica version 2;
- client 0.26-0.28 possono continuare a leggere v1 ignorando `activity`;
- i file v2 già presenti vengono ancora importati e, al successivo sync
  scrivibile, convergono al writer v1 additivo.

## Deduplica background

Il watcher Android passa dal solo timestamp a un cursore per ID evento.

- ID validato come SHA-256 esadecimale;
- eventi duplicati non producono una seconda notifica;
- eventi con lo stesso timestamp restano distinguibili;
- il vecchio timestamp viene usato come baseline di migrazione;
- massimo 400 ID recenti conservati per spazio;
- il cursore avanza anche se il canale notifiche è spento;
- una nuova sessione dopo disattivazione crea una baseline per evitare backlog.

## Notifiche Android

La diagnostica distingue:

1. permesso runtime POST_NOTIFICATIONS;
2. stato globale delle notifiche dell'app;
3. stato specifico del canale `shared_space_updates`.

La schermata Shared Spaces può:

- richiedere il permesso;
- aprire direttamente le impostazioni del canale;
- inviare una notifica locale di test usando lo stesso canale reale.

## Background restrictions

Lo stato nativo espone `ActivityManager.isBackgroundRestricted`.

Se Android mette Notes in modalità Restricted, l'interfaccia lo segnala e
consente di aprire le impostazioni dell'app. Non viene richiesta
automaticamente un'esenzione dalle ottimizzazioni batteria e non viene aggiunto
un foreground service permanente.

WorkManager resta la primitive corretta per questo polling: il repeat interval
configurato è 15 minuti ma l'esecuzione è deliberatamente non esatta e può
essere ritardata da Doze, risparmio energetico e policy OEM.

## Retry policy

- constraint: rete CONNECTED;
- retry transient: backoff esponenziale da 30 secondi;
- 408, 429, 5xx e rate limit GitHub sono transitori;
- errori 4xx permanenti/configurazione vengono esposti in diagnostica senza
  creare un ciclo di retry aggressivo;
- repository privato e scrivibile verificato prima della scansione.

## Reboot e limiti di sistema

Il periodic work resta registrato tramite WorkManager e viene ripristinato dopo
un normale reboot Android. Un force-stop o una restrizione background esplicita
dell'utente può invece impedire l'esecuzione finché il sistema/app non la
riabilita: il codice non tenta di aggirare questa scelta.

## Acceptance

La release è accettata solo con:

- dart format gate;
- flutter analyze;
- Flutter tests inclusi compatibility/status tests;
- compilazione Kotlin dentro APK debug;
- release split-per-ABI con R8/resource shrinking;
- size gate arm64;
- upload APK e simboli.

Resta necessario un acceptance test su dispositivo reale per verificare la
comparsa della notifica nella tendina e il comportamento specifico OEM.
