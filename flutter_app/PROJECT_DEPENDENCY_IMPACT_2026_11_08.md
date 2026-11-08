# Step 5 · Project Intelligence #51 — impatto dei prerequisiti visibili

## Nuova capability incrementale
- `ProjectDependencyImpactReview.inspect` deriva dai `ProjectWorkItem` già visibili e autorizzati in un progetto, con limite 5.000; non esegue alcuna scrittura né crea nuove tabelle.
- Conta **solo i task che citano direttamente** ogni prerequisito esplicito `dep_<id>`, deduplicando tag e ignorando sorgenti/targhet completati, cancellati, archiviati, mancanti o non univoci. Non mostra ID o titoli fuori dallo scope.
- Ordine deterministico: numero di dipendenti diretti decrescente e taskId crescente a parità; mostra massimo cinque prerequisiti, ciascuno con fino a tre titoli dei task che lo citano.
- La vista Project Workspace offre un riquadro read-only dei prerequisiti più citati, aprendo il task canonico esistente. Non modifica WIP, date, assenze, stati, schedule o permessi.
- Test: duplicati, target completati/non visibili, 5.000 task, output bounded, nessuna mutazione della lista note.

**Interpretazione rigorosa:** essere prerequisito di più task NON prova che completarlo sbloccherà tutti i task; potrebbero esistere altri vincoli. La UI comunica il numero di riferimenti, senza promettere la soluzione del blocco.

## Scopo residuo #51
Resta da completare la scrittura delle priorità/dipendenze con serializzazione e test di concorrenza trans-store, date/durate esplicite, schedule confermabile, benchmark Android 500/5000, user journeys, QA accessibilità, account switch. Questa è un'implementazione incrementale verificabile, NON la chiusura dell'intera capability.
