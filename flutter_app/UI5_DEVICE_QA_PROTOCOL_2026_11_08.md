# UI5 · protocollo di collaudo, evidenze e rilascio sicuro

**Ambito:** Notes-Ecosistema main di partenza f11ca0bee1594ccf95ca2876a1df0c658459aeb4, Factory Core baseline 3481a8190a5db5965bb22f84832094268d05be98 (Master v27 / Index v28).
**Stato:** suite widget automatica + ricetta APK QA implementate; collaudo Android fisico **NON ESEGUITO**. Issue #85.

## Esecuzione automatica
- flutter test --no-pub test/ui5_layout_matrix_test.dart
- Flutter Port CI esegue test UI5, analisi e Android. In questa PR genera un APK DEBUG **separato** con package it.notes.ecosystem.lymlyc.ui5qa e nome Notes UI5 QA; in futuro si può avviare manualmente il workflow_dispatch su main con production_signed=false.
- Artefatto: Notes-UI5-QA-debug-NOT-FOR-PRODUCTION con APK, SHA256 e questo documento. Il pacchetto QA non condivide lo spazio dati con Notes installata.
- Flutter define applicati **solo all'APK QA**: NOTES_UI5_HOME_PREVIEW=true e NOTES_UI5_NAV_PREVIEW=true. Non attivare NOTES_QA_SMART_INBOX_PROJECT_LINK.
- I normali APK/AAB mantengono UI5 default OFF. La CI debug non fornisce una firma update compatibile con il package originario.

## Matrice obbligatoria per collaudo manuale (registrare PASS/FAIL e screenshot)
1. 320, 360, 393, 600, 900, 1280dp; verificare 5 tab mobile sotto 900 e 6 Rail desktop.
2. Chiaro/scuro, font 100%, 130%, 200%, tastiera aperta e landscape; nessuna sovrapposizione, pulsante irraggiungibile o overflow.
3. Sei lingue en/it/es/fr/de/pt: hero e entry point UI5, voci NavigationBar. Verificare layout di testi lunghi.
4. Spazio vuoto, 20 note, 500 note, 5000 note **sintetiche**; 3 Continua, 2 Da rivedere (3 dopo Espandi), nessun item cestinato/archiviato/non autorizzato.
5. Ricerca nell'AppBar -> route canonica Search indice 5; ritorno Note, backstack, Ctrl+K, Ctrl+Shift+F e deep link task/diario/spazi.
6. Tap e navigazione di Sketchbook, Study, Automations, Graph, Project, Privacy Copy, Document Delta, Focus e raccolte.
7. TalkBack, focus tastiera, contrasto, touch target 48dp; nessuna azione implicita o dipendenza dal solo colore.
8. Account switch, sync, ripristino bloccato e revisione dati: nessuna perdita di note, nessun collegamento progetti automatico.
9. Su Android fisico registrare modello, API, densità schermo, orientamento, durata/fps/jank della Home, PSS memoria, commit SHA e checksum APK.

**Non confondere** test widget o build verde con la certificazione hardware. Non usare questo APK per aggiornare Notes reale. Non chiudere #85 né abilitare le UI per tutti senza evidenze e sign-off. #71 firma production, #75 restore, #46 Smart Inbox restano indipendenti.
