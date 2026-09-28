# Notes Ecosistema 0.46 — Consolidation & Quality Sweep

## Obiettivo

Consolidare la baseline 0.45 senza aggiungere nuovi sottosistemi. Lo step applica Rule Zero: correggere incoerenze reali, rendere espliciti i contratti lifecycle e non introdurre refactor preventivi.

## Universal Delete & Lifecycle audit

| Entità / dominio | Trash / restore | Purge / cleanup | Decisione 0.46 |
|---|---|---|---|
| Note e task | Core esistente | draft, revisioni e ContentBlock | invariato |
| Template | è una Note archiviata | segue lifecycle Note | invariato |
| Properties | segue la Note | valori rimossi al purge | confermato |
| Research / Relations | segue la Note | fonti e relazioni rimosse al purge | confermato |
| Derivatives / OCR | derivati della source | rimossi al purge della Note | confermato |
| PDF annotations | legate a Note + asset | rimosse al purge della Note | confermato |
| Project links | proiezione, non ownership | link rimossi al purge della Note | confermato |
| Project Workspace | lifecycle proprio | eliminare progetto non elimina note/task | confermato |
| Shared Spaces | unlink con controllo permessi | unlink prima del purge | confermato |
| Study | LearningItem con snapshot storico | non viene cancellato automaticamente col source purge | intenzionale: lo storico resta leggibile |
| Reminder | solo contenuti attivi | esclusione automatica per trash/archive/completed | confermato |
| Attachment CAS | content-addressed | cleanup solo se nessun riferimento resta | rafforzato in 0.46 |

## Fix concreto 0.46

Il cleanup degli allegati considerava i link presenti nei body e nei draft, ma non i riferimenti conservati nei sidecar Documents/Derivatives. Un PDF poteva quindi essere ancora necessario a un'annotazione o a una derivazione OCR anche dopo la rimozione del link Markdown.

La reachability degli asset ora include:

- body di tutte le Note;
- draft non ancora salvati;
- sourceAssetKey dei Derivatives/OCR;
- assetKey delle annotazioni PDF.

La policy è volutamente conservativa: un cleanup non deve mai trasformarsi in perdita dati.

## Cosa non viene fatto

- nessun nuovo database;
- nessuna migration di schema;
- nessun CRDT globale;
- nessun Feature Pack runtime;
- nessun nuovo renderer;
- nessuna AI;
- nessuna cancellazione automatica dei LearningItem quando la source viene purgata;
- nessuna eliminazione speculativa di codice legacy necessario alla compatibilità.

## QA

- regressione dedicata alla reachability degli allegati;
- suite esistente lifecycle / backup / Study / Documents / Visual invariata;
- chiusura release subordinata ai gate CI standard FAST/FULL.
