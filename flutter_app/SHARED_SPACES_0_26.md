# Shared Spaces 0.26

## Obiettivo

Shared Spaces aggiunge collaborazione selettiva a Notes Ecosistema senza trasformare il workspace personale in uno spazio pubblico o condiviso. Ogni contenuto resta privato per default e diventa condiviso solo dopo un’azione esplicita.

## Modello di sicurezza

- Nessun contenuto viene aggiunto automaticamente a uno spazio.
- Rimuovere un elemento da uno spazio non elimina la nota o attività locale.
- Rimuovere uno spazio dal dispositivo non elimina i contenuti locali.
- Gli inviti NS26 non contengono password, token GitHub o altri segreti.
- Gli inviti scadono e non possono assegnare il ruolo Proprietario.
- Un Viewer non può modificare note, attività, Sketch o Whiteboard ricevuti nello spazio.
- Room v8 non viene migrato: appartenenza, ruoli e tombstone Shared Spaces sono metadati separati.

## Ruoli

**Proprietario**
- modifica lo spazio;
- invita e rimuove membri;
- assegna Editor/Viewer;
- aggiunge e rimuove contenuti.

**Editor**
- legge e modifica i contenuti dello spazio;
- aggiunge o rimuove contenuti;
- non gestisce membri o proprietà.

**Viewer**
- sola lettura;
- può navigare note, attività e documenti visuali;
- non modifica i contenuti né l’appartenenza allo spazio.

## Dati e merge

Ogni spazio mantiene clock separati per:
- nome e descrizione;
- membri/ruoli/rimozioni;
- aggiunta e rimozione di ogni contenuto.

Aggiunta e rimozione usano tombstone e clock monotoni, così un merge tra due copie dello stesso spazio determina quale operazione è più recente senza richiedere una migrazione del database note.

## Pacchetto Shared Space

Formato ZIP: `notes-ecosystem-shared-space-bundle` v1.

Contiene:
- `space.json`: metadati, membri, ruoli e clock;
- `documents/*.md`: solo note/attività/documenti esplicitamente condivisi;
- `assets/*`: solo allegati referenziati dai documenti inclusi;
- `LEGGIMI.txt`.

Durante l’import vengono verificati:
- whitelist dei percorsi ZIP;
- duplicati;
- limiti di dimensione;
- ID e filename documenti;
- formato Sync v6;
- SHA-256 degli allegati;
- corrispondenza completa fra membership, documenti e asset.

## Conflitti contenuto

Durante l’import:
- elemento assente localmente → viene ricevuto;
- stesso contenuto → nessuna azione;
- remoto più recente → remoto applicato;
- locale più recente → locale conservato;
- timestamp uguale ma contenuto diverso → copia conflitto separata.

Nessun conflitto viene risolto sovrascrivendo silenziosamente entrambe le versioni.

## Limiti 0.26.0

La 0.26.0 implementa il core collaborativo e lo scambio portabile/offline tramite pacchetti verificati. Non implementa ancora:
- account cloud centralizzati;
- push real-time;
- presenza online;
- editing concorrente in tempo reale;
- trasporto automatico dei Shared Spaces.

Queste funzioni appartengono alla fase Live Sync successiva e possono riutilizzare il modello di ruoli, membership, clock e merge introdotto qui.
