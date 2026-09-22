# Aggiornamento 0.9

Il formato delle nuove scritture è v2 e conserva pinned/archived. Si leggono anche file e checkpoint v1. Aggiornare tutti i dispositivi a 0.9; dettagli in AGGIORNAMENTO_090.md. Le istruzioni operative sotto restano valide; gli esiti di test riportati sotto sono storici.

# GitHub sync — implementazione 0.7

## Collegamento nell'app
1. Su GitHub crea un repository, preferibilmente privato, inizializzato con README.
2. Crea un personal access token fine-grained limitato a quel repository con
   Contents: Read and write. Non inserire token nel prompt AI Studio o nei sorgenti.
3. In Impostazioni indica proprietario, repository, ramo esistente (es. main),
   cartella dedicata (es. notes-ecosystem) e token. Autorizza lo scambio e collega.
4. Ripeti sul secondo telefono per confrontare note e conflitti.

L'accesso usa un token inserito dall'utente; il login OAuth via pulsante non è incluso.
Il token viene cifrato AES-GCM con chiave Android Keystore, in noBackupFilesDir.
I repository pubblici richiedono consenso specifico. La visibilità viene ricontrollata
ad ogni sync. Nessun server o segreto applicativo condiviso deve essere configurato.

## Formato e concorrenza
Un file Markdown per ID nota; nome SHA-256 dell'ID, prima riga metadati JSON in commento
HTML e corpo testo esatto nelle righe successive. Conservare prima riga e nome del file
quando si modifica il corpo da GitHub. Nuove note si creano nell'app: importazione di
Markdown arbitrario senza metadati non implementata. Il formato è interoperabile come
testo, non compatibile automaticamente con i database di altri prodotti.

Lettura remota ancorata a un commit; confronto a tre vie con ultimo contenuto comune.
Scritture sequenziali tramite Contents API, con SHA atteso per file. Nessun force push.
Checkpoint locale dopo ogni file. Il sync può essere parziale e riprendere: non è una
transazione unica dell'intero repository. Le operazioni Room in ingresso sono atomiche.
I conflitti conservano locale/remoto fino a scelta esplicita (locale, remoto, entrambe).
La scelta viene rifiutata se le versioni visualizzate o la nota sono cambiate.
Note aperte o con bozza non sono sovrascritte: chiudere/salvare/scartare e riprovare.
Le cancellazioni dell'app sono tombstone con contenuto conservato nel cestino.
La rimozione esterna di un singolo file è convertita in tombstone; se l'intera cartella
risulta vuota/rimossa dopo un precedente sync, l'app si ferma e chiede di ripristinare
i file su GitHub. Questo vale anche per la cancellazione dell'unica nota remota.

## Background e limiti
Dopo modifiche locali viene accodato lavoro con rete disponibile; controllo periodico
ogni 15 minuti come intervallo richiesto, non come garanzia temporale Android.
Retry per problemi di rete/servizio e conflitti HTTP; rate-limit con attesa persistente.
App forzatamente arrestata e restrizioni batteria possono ritardare il lavoro.
Scollegamento serializzato con il sync: conserva note e checkpoint sul telefono;
non revoca il token su GitHub, che si può revocare nelle impostazioni GitHub.

500 note cestino incluso, 256 KB per nota, 5 MB per insieme locale/remoto. Cartella
con 1000 elementi rifiutata perché la Contents API potrebbe fornire elenco incompleto.
Bozze, cronologia e raccolte vuote non vengono sincronizzate. Gli ID delle raccolte
sono locali; il collegamento remoto conserva il nome della raccolta. File/allegati,
Note a due, cifratura end-to-end e server GitHub Enterprise non sono inclusi.

## Fonti API consultate
https://docs.github.com/en/rest/repos/contents
https://docs.github.com/en/rest/git/refs
https://docs.github.com/en/rest/authentication/authenticating-to-the-rest-api
https://developer.android.com/jetpack/androidx/releases/work
