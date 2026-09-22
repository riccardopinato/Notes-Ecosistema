# Notes — Ecosistema 0.12.0 · Identità editoriale

VersionCode 14. Baseline: ZIP utente (6), versione 0.11.0. Aggiornamento dell’interfaccia, senza nuove dipendenze.

## Modifiche visibili e collegamenti reali
- Palette avorio/cobalto/terra conservata, anche nel tema scuro. Tipografia serif estesa ai titoli di sezione e al Focus; superfici con bordi discreti, spaziature e forme coerenti. Testate riducono gli elementi secondari quando il carattere di sistema supera 1,3×.
- Home: hero editoriale con data, pulsante Scrivi una nota, contatori reali e cliccabili, agenda con tre attività di oggi/scadute e accesso all’agenda completa. Il pulsante del totale attività apre Tutte, quello dell’agenda apre Oggi. Nessun dato dimostrativo.
- Scheda Focus della Home: accesso al planner e testo diverso se esiste una sessione locale; stato riletto all’ingresso e al ritorno in primo piano, senza polling continuo. Agenda elaborata su Dispatchers.Default, legata ai suoi input; data aggiornata ogni minuto mentre la Home è aperta.
- Navigazione inferiore comune a libreria e planner, conservando accesso alle checklist e alle cinque sezioni. Il planner non rimane più una schermata isolata dalla navigazione principale.
- Schede note: bordo e selezione più riconoscibili, transizione colore di 180 ms, data di modifica leggibile, anteprima limitata, tag e stato sync conservati. Menu, preferiti, fissate, archivio e cestino mantengono le azioni precedenti.
- Attività: titoli editoriali per ciascuna vista, data leggibile, badge testuali per scadenza/priorità/completamento, Focus in evidenza e stato vuoto dedicato. Colore accompagnato da testo, senza cambiare le regole delle attività.
- Focus: pannello cobalto, conto alla rovescia serif, avanzamento visivo, registrazione e scarto collegati alle stesse operazioni della v0.11. Nessuna notifica o funzione timer aggiuntiva.
- Editor: raccolta e tag su una riga scorrevole per lasciare spazio al testo. Barra Markdown compatta a icone, ciascuna con descrizione accessibile; stessi comandi di formattazione e gestione selezione/link. Testata coerente, salvataggio/bozze/cronologia preservati.
- Raccolte, ricerca e impostazioni: titoli e descrizioni coordinati. I filtri, le operazioni multiple e tutte le funzioni esistenti restano raggiungibili.

## Verifiche e limiti effettivi
Confronto dei file: dominio, persistenza, sincronizzazione, test JVM/strumentali e schemi forniti sono byte per byte identici alla baseline 0.11. Il controllo sintattico Kotlin non ha rilevato errori di sintassi nella prima revisione UI; non è una compilazione Android e non verifica riferimenti Compose. Le revisioni finali richiedono build Android.
Non è stato possibile compilare o visualizzare l’app Android qui: il collaudo grafico deve avvenire in AI Studio e su dispositivo. Non vengono dichiarati screenshot, prove di fluidità o controlli di accessibilità su hardware non eseguiti.
La baseline contiene 154 test JVM dichiarati superati dall’utente; non sono rieseguiti localmente per questo restyling e non verificano automaticamente la resa grafica. AI Studio deve eseguire la build e la suite Gradle e riportare gli esiti reali.
Room rimane 6, backup/sync v4, applicationId e firma invariati. Nessuna migrazione. Conservare gli schemi 2/3/4/6 ricevuti; lo schema 5 non è incluso nell’export utente e non va inventato per questo aggiornamento.
Le prove ancora aperte della v0.11 (strumentali, timer reale e GitHub fra due dispositivi) restano aperte.

## Collaudo richiesto in AI Studio
1. Applicare tutti i file e compilare APK; eseguire testDebugUnitTest. Verificare la presenza di HomeOverview, EcosystemNavigation, EditorialAppTitle, EditorialBadge e dei nuovi richiami dal planner.
2. Aprire Home con archivio vuoto e popolato, con bozze, attività oggi/scadute/future e sessione Focus. Contatori e agenda devono riflettere i dati, e i pulsanti devono aprire le viste corrette.
3. Navigare tra tutte le sezioni dalla libreria e da Attività, aprire la nota collegata, tornare, passare alle checklist e di nuovo al planner.
4. Provare selezione multipla, preferiti, fissate, tag, archivio/cestino, ricerca combinata e raccolte; tutte le funzioni devono restare operative.
5. Editor: aprire tastiera, formattare selezioni con ogni icona, inserire link, cambiare modalità, tag/raccolta, salvare/scartare/recuperare bozza e aprire cronologia. Verificare spazio utile su display piccolo.
6. Tema chiaro/scuro, font 1×/1,3×/2×, TalkBack e larghezze 320/360 dp: controllare titoli, menu, chip scorrevoli e pulsanti. Le icone Markdown devono annunciare il comando, non il simbolo.
7. Focus: controllare avanzamento e durata, uscita/rientro, conferma/scarto e assenza di doppio conteggio; la navigazione non deve cambiare il timer.
8. Verificare scorrimento con molte note/attività su dispositivo. Non dichiarare prestazioni misurate sulla sola base della compilazione.
