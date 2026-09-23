# Shared Spaces Authenticated Identity 0.27.0

## Obiettivo

La 0.27.0 rende stabile l'identità di collaborazione tra installazioni diverse di Notes senza introdurre un secondo backend.

Shared Spaces continua a usare il repository GitHub privato configurato dall'utente, ma il profilo di collaborazione viene ora associato all'account GitHub realmente autenticato dal token.

## Identità stabile

Al primo Live Sync o sync manuale:
- Notes interroga GitHub `/user`;
- verifica ID numerico e login dell'account;
- deriva l'ID canonico Shared Spaces come `github:<user-id>`;
- conserva l'ID locale 0.26.x tra gli alias di migrazione;
- riscrive localmente solo la membership dello stesso utente;
- al sync successivo normalizza anche la vecchia membership remota.

Questo evita che lo stesso account venga trattato come persone diverse su due dispositivi nuovi.

## Migrazione 0.26.x

Gli spazi esistenti non vengono cancellati.

Per proprietari, editor e viewer già presenti:
- l'ID precedente viene mantenuto come alias locale;
- ruolo e clock vengono preservati;
- la proprietà dello spazio viene trasferita all'ID canonico solo quando il vecchio proprietario è l'identità locale in migrazione;
- il merge accetta la copia remota legacy normalizzandola prima del confronto.

Una volta pubblicato lo stato canonico dal dispositivo aggiornato, le nuove installazioni che usano lo stesso account GitHub convergono sullo stesso ID.

## Protezione cambio account

Se un profilo con Shared Spaces esistenti è già associato a un account GitHub, Notes rifiuta l'associazione automatica a un account GitHub diverso.

Questo impedisce che un semplice cambio token trasferisca accidentalmente ruoli o proprietà.

## Compatibilità

- formato locale Shared Spaces: compatibile con versione 1;
- inviti `NS26`: ancora validi;
- ZIP Shared Space 0.26: ancora validi;
- Live Sync 0.26.1: compatibile;
- nessun reset database;
- nessuna nuova dipendenza Flutter.

## Limiti ancora intenzionali

La 0.27.0 non introduce:
- backend Notes proprietario;
- autorizzazione server-side dei ruoli Notes;
- WebSocket;
- presenza/cursori live;
- CRDT/OT;
- notifiche push;
- servizio permanente a app chiusa.

I permessi effettivi del repository GitHub restano separati dai ruoli owner/editor/viewer dell'app.
