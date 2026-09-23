# Shared Spaces Remote Discovery 0.27.1

## Obiettivo

La 0.27.1 completa il Live Sync multi-dispositivo della serie 0.27.

Una nuova installazione collegata allo stesso repository GitHub non dipende più
dalla presenza preventiva di Shared Spaces locali: Notes scandisce la cartella
remota `shared/`, legge gli stati degli spazi disponibili e importa solo quelli
in cui l'identità GitHub autenticata risulta membro attivo.

## Comportamento

- identità canonica invariata: `github:<user-id>`;
- nessun backend aggiuntivo;
- nessuna nuova dipendenza Flutter;
- discovery limitata alle directory Shared Spaces valide;
- spazi remoti non accessibili all'utente vengono ignorati;
- massimo locale invariato: 30 Shared Spaces;
- gli spazi scoperti entrano nello stesso merge a clock della 0.26/0.27;
- la sincronizzazione continua a preservare conflitti e copie locali;
- una installazione senza spazi locali può ora ricevere gli spazi già
  pubblicati nel repository.

## Sicurezza

La discovery non concede nuovi permessi. Uno spazio remoto viene adottato solo
se lo stato remoto valido contiene l'identità canonica autenticata tra i membri
attivi. I ruoli owner/editor/viewer continuano a essere applicati dal dominio
Shared Spaces.

## Compatibilità

- Shared Spaces v1 invariato;
- inviti NS26 invariati;
- ZIP 0.26 invariati;
- Live Sync 0.26.1 e identity migration 0.27.0 compatibili;
- nessuna migrazione database richiesta.
