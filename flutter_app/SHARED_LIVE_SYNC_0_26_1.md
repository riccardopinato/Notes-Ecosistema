# Shared Spaces Live Sync Foundation 0.26.1

## Scopo

La 0.26.1 porta Shared Spaces dal solo scambio manuale di pacchetti a una sincronizzazione automatica multi-dispositivo basata sul repository GitHub privato già collegato a Notes.

Il workspace personale resta separato: il motore Live Sync pubblica esclusivamente gli spazi condivisi e i contenuti che appartengono esplicitamente a ciascuno spazio.

## Trasporto

Ogni Shared Space usa una cartella dedicata derivata in modo deterministico dall'ID dello spazio:

`<cartella Notes>/shared/<hash spazio>/`

Dentro la cartella remota vengono mantenuti:
- `space.json` con membership, ruoli e clock;
- documenti Markdown Sync v6 dello spazio;
- `assets/` con soli allegati referenziati dai documenti condivisi.

Il repository deve essere **privato** e il token GitHub deve avere accesso Contents in lettura/scrittura.

## Ciclo automatico

Quando Live Sync è abilitato:
- parte un tentativo iniziale;
- viene pianificato un controllo circa ogni 90 secondi mentre Notes è aperta;
- una modifica a uno Shared Space richiede un nuovo sync a breve;
- un sync manuale resta sempre disponibile;
- errori transitori non cancellano né modificano i dati locali.

La 0.26.1 non mantiene un servizio Android permanente quando l'app è chiusa.

## Merge e conflitti

Per ogni documento viene conservato localmente solo l'hash della base sincronizzata. Questo consente un three-way decision senza duplicare l'intero contenuto nello stato di sync:

- locale = remoto → nessuna azione;
- locale = base → download remoto;
- remoto = base → upload locale;
- entrambi diversi dalla base → conflitto.

Al primo sync, senza base, il timestamp `updatedAt` determina quale copia è più recente. A parità di timestamp e contenuto diverso viene trattato come conflitto.

Nei conflitti la copia locale viene preservata come nota separata prima di applicare la versione remota canonica. Non avvengono sovrascritture silenziose.

## Ruoli

- **Owner / Editor**: sincronizzazione bidirezionale.
- **Viewer**: ricezione remota; eventuali modifiche locali inattese non vengono pubblicate come contenuto dello spazio.
- Le modifiche a membership e ruoli continuano a usare i clock/tombstone introdotti nella 0.26.0.

I ruoli applicativi non sono un sostituto dei permessi GitHub: chi possiede accesso diretto in scrittura al repository può modificare i file fuori dall'app. Un backend account proprietario potrà rendere questi ruoli un confine di autorizzazione server-side in una fase successiva.

## Privacy

- repository pubblico rifiutato dal motore Shared Live Sync;
- nessuna nota privata viene enumerata o caricata perché non appartiene a `contentIds`;
- quando un contenuto viene rimosso dallo spazio, Owner/Editor rimuovono il documento remoto non più condiviso;
- gli allegati remoti non più referenziati vengono eliminati;
- allegati verificati con SHA-256;
- percorsi e formati restano validati.

## Concorrenza

Gli upload GitHub usano gli SHA attesi. Errori 409/422 causano fino a tre retry con rilettura dello stato locale. Al termine di un sync, il risultato remoto viene nuovamente fuso con lo stato locale corrente, così una modifica effettuata mentre il sync era in corso non viene persa.

## Limiti intenzionali

Questa è una **Live Sync Foundation**, non ancora collaborative editing real-time:
- niente cursori/presenza live;
- niente WebSocket;
- niente editing simultaneo CRDT/OT;
- niente notifiche push server-side;
- niente sync permanente a app chiusa;
- nessun account Notes proprietario separato dall'identità/permessi GitHub.

I pacchetti ZIP Shared Space della 0.26.0 restano supportati come fallback offline e migrazione.
