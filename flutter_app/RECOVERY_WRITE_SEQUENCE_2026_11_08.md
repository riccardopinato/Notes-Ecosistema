# Step 3 · Restore cross-store: sequenza nominata e fault injection

**Baseline:** Notes main f11ca0bee1594ccf95ca2876a1df0c658459aeb4. Issue #75; issue #72 per riproducibilità.

## Incremento verificabile nel codice
- La funzione di ripristino effettivamente usata dall'app chiama RecoveryWriteSequence.run e passa le **11 scritture reali** nell'ordine deterministico: assets, notes, properties, knowledge, derivatives, shared, projects, study, documents, imports, automations.
- La sequenza rifiuta chiavi mancanti/supplementari prima di scrivere ed espone un hook di fault-injection **esclusivamente nei test**. Non aggiunge flag o comportamenti runtime di corruzione.
- Il journal già esistente e RecoveryTransaction gestiscono snapshot, marker durevole, rollback/re-entry. Non cambiamo schema, destinatari, ordini di sync o gestione di file CAS.
- I test iniettano errori *dopo ognuna delle 11 fasi* usando la stessa sequenza di produzione; verificano che l'outer journal richiami rollback e impedisca la prosecuzione.

## Gate ANCORA APERTI
Questa suite verifica il coordinatore e i confini di scrittura con storage simulato, NON un test end-to-end con tutti i database reali su Android. Mancano ancora prove di kill process, low storage, directory fsync fisico, Android SAF, tempi/corruzione su file reali, ripristino di permessi Shared Spaces, hash/ID reali prima/dopo.
Per #72 la toolchain Flutter/pubspec.lock è pin, ma Gradle e template transitive devono essere congelati/verificati con due build indipendenti e manifest/SBOM. Non dichiarare riproducibilità totale. Mantenere #75 e #72 aperte fino ai gate real-device e due-build.
