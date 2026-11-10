# UX Step 7 — Study Sprint Studio (Notes-Ecosistema)

**Stato:** UX_APPROVED_PROVISIONAL (decisione utente 10/11/2026) / non installabile / NON ACQUISTABILE. **Data:** 10/11/2026. **Factory pinned:** App-Factory-Core@2953e9b50f5f43fbd5a1702cb41785a4235592a5 (Master 27 / Index 29).

[Prototipo HTML navigabile — SOLO dati sintetici](PROTOTIPO_STUDY_SPRINT_STUDIO.html) · Riferimento manifest già validato: [notes_study_sprint_studio_research.json](https://github.com/riccardopinato/App-Factory-Core/blob/main/contracts/template_engine_v1/examples/notes_study_sprint_studio_research.json).

## Decisioni da testare

1. **Scopri:** carta nativa in Modelli di Notes, separata dai template Free; etichetta esplicita «Concept, non acquistabile». Promessa limitata: fonte manuale + argomenti + domande personali + ripasso. Nessuna AI, nessun documento di terzi, nessun accesso non autorizzato.
2. **Prepara:** titolo, riferimento/fonte dichiarata, massimo 8 argomenti su righe, scelta di sezione domande e checkpoint; nessuna data indovinata, notifica automatica o contenuto caricato da cloud.
3. **Anteprima:** una Note dimostrativa renderizzata con stile Notes; testo e dati **inventati**. Il prototipo non mostra task salvati, né un database Study creato.
4. **Conferma:** differenza leggibile: una futura Note modificabile, nessun Task automatico; eventuali Task richiedono una successiva scelta esplicita + adapter transazionale validato. Toggle di conferma nel mockup sblocca solo «Simula creazione».
5. **Dopo:** nella versione reale la nota sarà modificabile e posseduta dal suo utente, anche se il template verrà rimosso. Non esiste ancora il runtime né il prodotto Premium.

## Ancoraggi tecnici da riusare, NON duplicare

- **Catalogo:** `flutter_app/lib/src/screens/templates_screen.dart`, `PageTemplates` e `PersonalTemplates` in `flutter_app/lib/src/domain/templates.dart`.
- **Dati:** `Note`, editor, writer già canonici. Il modulo Study Core esistente rimane owner dello studio; mai una nuova tabella/servizio parallelo.
- **Identità:** `it.riccardopinato.notes.study_sprint_studio` e `notes.study_sprint.v1` (adapter ID del manifest, NON classe implementata).
- **Billing:** `access.tier=paid_once` nel manifest è ricerca commerciale, non SKU, acquisto, paywall o entitlement verificato. I template Free esistenti rimangono gratuiti.
- **Originalità:** solo testi creati per il prototipo, nessuna importazione di note, quiz o media esterni. Nessun contenuto Notion in runtime.

## Gate per Product/UX approval

- Validare posizione card, testo di onboarding, fonte/provenance, impaginazione di anteprima, uno vs più writer e reale vantaggio rispetto al template «Studio» gratuito.
- Verificare che i prompt e le sezioni originali producano un valore **materialmente distinto** dall'attuale Notes Studio Free prima di vendere un pack.
- Accessibilità: 320/360dp, tablet, ingrandimento 200%, tastiera, target 44–48dp, focus/reader, reduced motion; localizzazioni IT/EN/ES/FR/DE/PT **da produrre nel runtime** (mock HTML solo IT).
- Test adapter futuri: cancel prima del commit = zero scritture, retry stesso request ID senza duplicati, revision/owner mismatch, limite quota, errore al secondo writer, rollback, offline + import/export/backup.
- **Decisione UX ricevuta:** prototipo approvato provvisoriamente il 10/11/2026. La revisione resta aperta. L'approvazione del prototipo non prova il valore commerciale né autorizza SKU, billing o una release. Prima dell'adapter Flutter reale servono il gate di Product Bible, l'owner dei dati e i test di scrittura/rollback.

**Evidenza di questo step:** solo file HTML/CSS/JS locale senza chiamate network, storage o API app. La verifica PR docs non è test Flutter/device, né certificazione Golden/Donor E5. Anna's Diary è una proposta distinta e indipendente.
