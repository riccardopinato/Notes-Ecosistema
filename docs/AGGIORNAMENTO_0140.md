# Notes — Ecosistema 0.14.0 · Le pagine collegate

VersionCode 16. Base: sorgenti locali completi v0.13.0 già consegnati; nessun nuovo export AI Studio successivo è stato ricevuto. Non è un rifacimento del progetto. Palette e struttura editoriale conservate.

## Funzioni applicate e accesso
- Crea → quattro modelli: Riunione, Progetto, Studio, Revisione settimanale. Sono note Markdown ordinarie, modificabili e salvate tramite l'editor e le bozze esistenti. Nessuna creazione automatica di attività del planner dai titoli del modello; le checklist rimangono checklist.
- Crea → Diario di oggi. ID deterministico basato sulla data locale ISO. Riapre la stessa pagina o bozza del giorno; non sovrascrive note già salvate. Un diario cestinato richiede il ripristino dal cestino. Una copia importata resta una copia con nuovo ID, distinta dal diario canonico del giorno. Due dispositivi che creano il diario offline generano lo stesso ID: il normale motore sync gestisce il conflitto, senza fusione automatica.
- Editor, barra sotto i comandi Markdown → Collega: scelta di una nota salvata (anche archiviata), ricerca per titolo, inserimento alla selezione. URI interno notes://note/UUID nel Markdown; rinominare la destinazione non rompe il collegamento. L'etichetta visibile conserva il titolo al momento dell'inserimento.
- Anteprima: toccare un link interno apre la nota tramite navigazione dell'app, senza intent esterni. Un ID mancante o cestinato mostra un messaggio. Link normali HTTP/HTTPS mantengono il comportamento precedente.
- Editor, riga metadati → Collegamenti e backlink: destinazioni in uscita e note salvate che rimandano alla pagina corrente. Escluse attività, disegni e note cestinate; comprese note archiviate. Le bozze delle ALTRE note non sono indicizzate fino al salvataggio; per i link in uscita si usa il corpo attuale dell'editor.
- Prima di aprire una nota collegata con modifiche pendenti: Salva e apri / Resta / Scarta e apri. La navigazione sostituisce l'editor corrente, liberando la protezione sync; Indietro riporta alla schermata precedente all'editor, non a una pila illimitata di note aperte.
- Indice: titoli Markdown ATX #–######, esclusi blocchi di codice; tocco porta il cursore alla riga in Scrivi. Non interpreta titoli Setext sottolineati. Da Anteprima/Checklist passare a Scrivi per usare l'indice.
- Trova: ricerca letterale, maiuscole facoltative, conteggio e selezione dell'occorrenza successiva. Sostituzione di tutte le occorrenze con conferma; include anche testo dentro link/codice, dichiarato nel dialogo. Risultato limitato a 200.000 caratteri. Annulla sostituzione ripristina il testo precedente solo finché il corpo non cambia; memoria della sessione, non cronologia persistente.
- Tutti i comandi Markdown precedenti, tag, filtri, operazioni multiple, disegni e Focus restano collegati. Solo pagina nasconde anche i nuovi strumenti.

## Dati, importazione e sincronizzazione
Room 7, backup/GitHub v5 e dipendenze INVARIATI. Nessuna migrazione aggiunta; non creare schemi inventati. Firma/applicationId/toolchain invariati. Richiesta la v0.13 completa come base, inclusa migrazione 6→7 e sketchbook.
I collegamenti sono testo Markdown. Backup JSON e sync li preservano senza nuove proprietà. Importa copie rimappa gli UUID interni delle note e delle bozze quando la destinazione è presente nello stesso backup. Non modifica il JSON dei disegni, il codice inline/fenced o i link immagine. Riferimenti a destinazioni non incluse nel backup rimangono invariati e possono risultare non disponibili; non si inventano note per completarli.
Il lettore dei link riconosce i link inline generati dall'app; non implementa tutti i costrutti CommonMark, link di riferimento o sintassi Obsidian [[titolo]]. GitHub/browser esterni non aprono gli URI interni come pagine web.
Non sono state importate librerie o porzioni di codice da repository esterni: implementazione originale adattata al progetto. I riferimenti funzionali restano nel catalogo delle idee; non dichiarare incorporato NotallyX/Lumen/timeto.me.

## Verifiche effettivamente eseguite
- Esecuzione Gradle `:app:testDebugUnitTest`: 181 test completati con successo (0 fallimenti, 0 errori, 0 saltati) conteggiati dai 20 file XML in `app/build/test-results/testDebugUnitTest`.
- Copertura nuova: identificatori e escaping link, codice escluso dal parsing, offset CRLF e titoli, rimappatura, ricerca letterale/case/limiti, ID diario, modelli, round-trip backup e codec GitHub (27 casi in KnowledgeTest).
- Test Android aggiunti: KnowledgeRepositoryTest (1 importazione reale Room con note/bozze) e TemplateEditorTest (3 casi di ciclo di vita: nuova bozza, bozza recuperata, nota preesistente). Prove androidTest aperte per esecuzione con ADB su dispositivo o emulatore.
- Schemi storici confrontati byte per byte e rimasti invariati (Room schema v7 preservato).

## Prove ancora aperte e istruzioni AI Studio
Compilare APK e :app:testDebugUnitTest sul progetto effettivo. Contare tests/failures/errors/skipped dai report XML. Eseguire androidTest quando è disponibile ADB, incluse migrazioni e test dei passi precedenti.
Aprire Crea e ciascun modello; modificare, ruotare, uscire e recuperare la bozza. Diario: riapertura stessa data, cambio giorno, cestino/ripristino. Note A/B: inserire link, rinominare B, aprire da anteprima, verificare backlink, provare bozza sporca con le tre scelte. Importare un backup A/B e verificare che le copie puntino alle copie. GitHub fra due installazioni: link, diario creato offline su entrambe, conflitto esplicito.
Indice e ricerca con Unicode/CRLF, tastiera aperta e schermata piccola; sostituzione/annullamento e stili chiaro/scuro, font 1.3x/2x, TalkBack. Controllare che Salva resti raggiungibile.
Restano aperti anche collaudo sketchbook/PNG, timer Focus e sync live precedenti. Nessuna schermata Android visualizzata in questo ambiente, nessun benchmark, nessuna build APK locale dichiarata. Nessun dato fittizio inserito.
