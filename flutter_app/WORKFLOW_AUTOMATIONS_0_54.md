# Notes Ecosistema 0.54 — Workflow Automations

Workflow Automations introduce regole locali **evento → azione** sopra gli oggetti canonici già esistenti. Non crea un secondo sistema di Note/Task e non richiede AI, rete o account.

## Trigger

- elemento creato;
- elemento aggiornato;
- attività completata.

La valutazione avviene prima del salvataggio canonico. Una singola operazione utente produce al massimo una singola passata deterministica delle regole: le modifiche generate dalle automazioni non vengono reinserite nel motore e non creano loop.

## Condizioni

Ogni regola può limitarsi a:

- Note, Task oppure entrambi;
- presenza di un tag;
- testo contenuto nel titolo.

Le condizioni sono opzionali e combinabili.

## Azioni 0.54

- aggiungi tag;
- sposta in una raccolta esistente;
- fissa elemento;
- imposta priorità Task.

Sono intenzionalmente escluse in questa release:

- eliminazioni;
- invii o chiamate di rete;
- azioni su Shared Spaces remoti;
- scheduler/background trigger;
- AI;
- automazioni distruttive o difficili da annullare.

## Persistenza e audit

Le definizioni e lo storico minimale vivono in `notes-automations.db`.

Lo storico registra solo:

- regola;
- ID dell'oggetto;
- trigger;
- tipo di azione;
- timestamp.

Non duplica titolo, corpo o altri contenuti della Note/Task. Il purge definitivo di un oggetto elimina le sue righe di audit; le regole generiche restano.

## Portabilità

- Disaster Recovery v2 include `automations.json`;
- il decoder resta compatibile con Disaster Recovery v1, che viene interpretato come privo di automazioni;
- Open Export include `automations.json`;
- Media Bundle/import-as-copy non importa automazioni, per evitare di trasferire regole con target locali ambiguamente rimappabili.

## Web Preview

La Web Preview usa le stesse funzioni pure di valutazione ma conserva le regole demo solo in memoria. Questo permette di verificare trigger, azioni e UI da PC senza simulare una persistenza SQLite browser che la release Android non usa.

## Localizzazione base v14

La 0.54 introduce il contratto di localizzazione nativa:

- lingua dispositivo/sistema di default;
- fallback inglese;
- override persistente in Profilo/Impostazioni;
- IT / EN / ES / FR / DE / PT;
- nuove superfici Automazioni localizzate.

Le schermate legacy vengono migrate progressivamente: questa release non dichiara ancora la traduzione integrale di tutto il prodotto.

## Gate

FAST:
- regole pure e idempotenza;
- trigger completamento Task;
- fallback locale.

FULL:
- format;
- analyze;
- suite test;
- APK debug;
- APK release split ABI;
- size gate;
- Evidence Bundle;
- build Web Preview.
