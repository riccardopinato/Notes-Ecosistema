# Shared Activity & Change History 0.29.0

## Obiettivo

La 0.29.0 aggiunge una cronologia collaborativa leggibile e sincronizzata agli
Shared Spaces, senza introdurre un backend proprietario.

## Activity Feed

Ogni Shared Space conserva fino a 200 eventi recenti:

- creazione spazio;
- modifica nome/descrizione;
- contenuto condiviso;
- contenuto reso nuovamente privato;
- modifica membri o ruoli;
- modifica di un documento condiviso;
- conflitto locale preservato.

Gli eventi contengono autore, timestamp, tipo e soggetto opzionale.

## Deduplicazione multi-device

Gli ID degli eventi sono deterministici e derivati da:

- spazio;
- tipo evento;
- soggetto;
- timestamp;
- identità autore.

Lo stesso cambiamento osservato da più device converge quindi su un solo evento.
Il merge ordina gli eventi dal più recente e applica il limite di 200 elementi.

## Stato remoto

`space.json` passa alla versione remota 2 aggiungendo `activity`.

La lettura resta retrocompatibile con la versione 1 usata dalla 0.26-0.28:
uno spazio v1 viene interpretato con cronologia vuota e aggiornato al formato
v2 al successivo sync scrivibile.

Il formato locale Shared Spaces v1, gli inviti NS26 e gli ZIP 0.26 restano
invariati.

## Unread

Notes mantiene localmente per ogni spazio il timestamp dell'ultima attività
letta.

- gli eventi generati dall'identità corrente non incrementano il badge;
- gli eventi remoti successivi all'ultima lettura sono conteggiati come nuovi;
- la lista Shared Spaces mostra il badge sul singolo spazio;
- è disponibile “Segna tutto come letto”;
- aprire uno spazio ne aggiorna automaticamente lo stato di lettura.

La cache locale della cronologia permette di consultare l'ultima attività anche
prima del successivo Live Sync.

## Limiti intenzionali

- massimo 200 eventi per Shared Space;
- nessun WebSocket;
- nessuna presence/cursori live;
- nessuna notifica push in questa versione;
- nessun backend aggiuntivo.

Le notifiche Android/background restano candidate per il successivo step.
