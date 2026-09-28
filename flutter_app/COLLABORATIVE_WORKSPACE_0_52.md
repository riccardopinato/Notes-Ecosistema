# Notes Ecosistema 0.52 — Collaborative Workspace

## Obiettivo

Evolvere la collaborazione senza introdurre un secondo sistema parallelo.

La 0.52 riusa:

- Shared Spaces come membership, ruoli, contenuto e Live Sync canonici;
- Project Workspace come proiezione del lavoro di team;
- Activity Feed e unread già esistenti;
- Note e Task come oggetti canonici.

## Cosa esisteva già e non viene duplicato

- ruoli Proprietario / Editor / Viewer;
- inviti NS26 a scadenza;
- membership persistente;
- GitHub Live Sync;
- merge non distruttivo;
- Activity Feed;
- unread e background sync;
- Project Workspace team basato su Shared Spaces.

## Aggiunte 0.52

### Discussione sincronizzata

Ogni Shared Space può contenere commenti workspace-level.

- tutti i membri, inclusi Viewer, possono commentare;
- Viewer resta read-only sui contenuti;
- autore e proprietario possono rimuovere un commento;
- autore può modificare il proprio commento;
- edit e delete sono clock-based e merge-safe;
- i commenti rimossi restano tombstone per impedire resurrection offline;
- limite: 500 commenti per spazio;
- massimo 2000 caratteri per commento.

I commenti fanno parte del Shared Space e quindi seguono lo stesso merge/live-sync del workspace.

### Inviti recenti persistenti

Il proprietario mantiene una cronologia locale degli ultimi inviti generati.

- non viene sincronizzata agli altri membri;
- non espone codici invito nel payload remoto dello spazio;
- permette di ricopiare un invito non scaduto;
- gli inviti scaduti possono essere puliti;
- massimo 50 record.

La cronologia entra nel normale snapshot locale e nel Disaster Recovery tramite SharedSpacesSnapshot.

### Lifecycle workspace esplicito

Sono distinti:

- **Lascia spazio**: rimuove la membership dell’utente e produce un tombstone sincronizzabile;
- **Rimuovi dal dispositivo**: dimentica soltanto la copia locale;
- **Rimuovi membro**: resta azione del proprietario;
- il proprietario non può lasciare lo spazio finché la proprietà non viene trasferita/chiusa con una futura policy esplicita.

Non viene introdotto un falso “Elimina per tutti” senza un protocollo di ownership adeguato.

### Project Workspace

I progetti team mostrano anche:

- numero membri;
- numero commenti attivi;
- ruolo corrente;
- indicazione che contenuti e discussioni derivano dallo Shared Space canonico.

## Scelte intenzionali

Non inclusi:

- CRDT globale;
- cursori realtime;
- presence realtime;
- ACL per blocco;
- chat separata;
- secondo database collaboration;
- nuovo account system;
- secondo sync engine;
- commenti su wrapper progetto locali.

## Rule Zero

La 0.52 aggiunge soltanto capacità mancanti sopra i sistemi collaborativi già esistenti.

Nessun dato canonico viene duplicato.
