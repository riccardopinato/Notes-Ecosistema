# Notes 0.14.1 — Cerca unificata

VersionCode 17. Intervento richiesto sulla schermata Cerca dopo lo screenshot dell'emulatore. Base: export10 con gli 8 file correttivi applicati, la cui build e i 205 test sono stati dichiarati superati da AI Studio. Non è stato ricevuto un ulteriore ZIP dopo quella correzione.

## Interfaccia
Un solo campo Cerca nel titolo, nel testo e nei tag, con pulsante Cancella ricerca. Rimossa l'intestazione ridondante Ritrova il filo sotto il titolo Cerca. Una sola riga Filtri (numero di categorie attive), Azzera quando utile, e icona elenco/griglia. Sotto si mostra solo il riepilogo delle condizioni effettivamente attive, con testo a capo.
Tutti i filtri sono in un pannello inferiore scorrevole: ambito Note attive/Inbox/Archivio/Cestino, tipo Testo/Checklist/Disegni, Solo preferiti/Solo fissate, raccolta, presenza/stato delle checklist, tag esistenti. Preferiti compare una volta sola. I chip vanno a capo; non richiedono scorrimenti orizzontali di ciascuna sezione. Mostra risultati chiude il pannello, Azzera filtri azzera anche il tipo di contenuto senza cancellare la query.
Eliminato il secondo campo Tag da cercare. I tag si selezionano tra quelli esistenti (più eventuali tag già attivi), senza limite artificiale ai primi 30. Per più tag resta la scelta tutti/almeno uno. La ricerca testuale nei tag resta disponibile nel campo principale.
I filtri si applicano immediatamente; chiudere il pannello mantiene le scelte. Non esiste una falsa azione Annulla. Nessuna riga duplicata ambito/tipo sotto SearchControls in Cerca. Le altre sezioni mantengono i controlli precedenti.
Seleziona note appare in Cerca solo in presenza di risultati o durante selezione già attiva. Le azioni multiple restano collegate. Messaggio vuoto specifico invita a cambiare parola o azzerare filtri, anche con query vuota.

## Preservato
Motore searchNotes, resultKey anti-risultati obsoleti, backup/GitHub v5, Room7, tutti i test, sketchbook, collegamenti, diario e Focus. QuickSyncTileService e correzioni export10 conservati. Nessuna dipendenza/migrazione. Colori, serif e forme provengono dal tema corrente.

## Verifiche
Confronto sorgenti: nessun file di dominio, persistenza, sincronizzazione, test o schema modificato. Solo UI ricerca e metadati versione/documentazione. Controllo sintattico Kotlin locale; non equivale alla compilazione Android/Compose. Nessun nuovo test unitario che replichi la disposizione UI. I 205 test precedenti sono conservati; non è dichiarata una nuova esecuzione Gradle o build APK in locale.
Da eseguire in AI Studio: build APK e suite JVM; aprire Cerca vuota/con risultati, campo unico e nessun filtro duplicato, pannello scorrevole, selezione tag AND/OR, reset totale mantenendo query, azzeramento query mantenendo filtri, elenco/griglia, archivio/cestino, combinazione Inbox/raccolta, preferiti ereditati dalla libreria, selezione multipla. Verificare tema chiaro/scuro, tastiera, schermo piccolo, font 1.3x/2x e TalkBack. Il pannello limita l'altezza dell'area filtri e tiene i pulsanti finali fuori dall'area scorrevole: verificarne la resa reale.
Nessun rendering Android o misura di prestazioni eseguiti localmente. Restano aperti tutti i collaudi fisici precedenti.
