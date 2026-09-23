# Collaboration UX & Sync Reliability 0.28.0

## Obiettivo

La 0.28.0 consolida Shared Spaces Live Sync dopo la discovery multi-dispositivo
della 0.27.1. Non cambia il formato remoto e non introduce backend o dipendenze
Flutter aggiuntive.

## Affidabilità

- scheduler automatico non più basato su un semplice timer periodico;
- retry progressivo: 15s, 30s, 1m, 2m, massimo 5m;
- il backoff viene azzerato dopo un sync riuscito;
- gli errori di rete/timeout e gli HTTP temporanei vengono distinti dagli errori
  di configurazione o autorizzazione;
- modifiche locali non generano retry aggressivi mentre il client è in backoff;
- il sync manuale resta disponibile.

## Stato connessione

Shared Live Sync espone quattro stati runtime:

- Inattivo;
- Online;
- Offline;
- Attenzione.

Offline indica errori di rete, timeout, rate limit temporaneo o errori server.
Attenzione indica errori che richiedono verifica dell'utente, per esempio
configurazione, autorizzazione o coerenza dei dati.

## Stato per singolo Shared Space

Ogni esecuzione riuscita espone un riepilogo per spazio con:

- elementi inviati;
- elementi ricevuti;
- conflitti preservati;
- file remoti rimossi;
- elementi in attesa.

La schermata Shared Spaces mostra ora lo stato direttamente sulle card e nella
pagina di dettaglio dello spazio.

## Compatibilità

- Shared Spaces v1 invariato;
- inviti NS26 invariati;
- ZIP 0.26 invariati;
- identity migration 0.27.0 compatibile;
- remote discovery 0.27.1 compatibile;
- nessuna migrazione database;
- nessuna nuova dipendenza.
