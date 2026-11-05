# Notes — Step 2: salvaguardia obbligatoria prima del ripristino

**Stato: modifica software e test deterministici, non collaudo Android fisico.**
Baseline: `main@d5f301838a0dcca270edcfd9babef19455fa0985` (0.56.3+74).
Questo incremento è separato dalla firma produzione, tracciata in #71 e PR #74.

## Comportamento

1. L'utente seleziona un archivio di ripristino; `DisasterRecoveryBundle.decode` valida manifest, file, riferimenti e allegati **prima di qualsiasi scrittura**.
2. L'utente conferma che un ripristino sostituirà i dati locali.
3. Notes costruisce un backup completo dello stato corrente, lo decodifica in memoria e richiede un salvataggio ZIP su un provider di documenti esterno.
4. **Obbligatorio:** l'utente riseleziona il file appena esportato dal document picker. `RecoverySafety.requireVerifiedExternalCopy` confronta ogni byte con lo ZIP generato. Annullamento, file nullo, troncato o modificato bloccano l'operazione senza toccare i database.
5. Solo dopo il confronto vengono scritti allegati, SQLite e gli store derivati in sequenza.
6. Un'esportazione backup ordinaria annullata non mostra il messaggio di successo.

## Copertura automatica e limiti

- `test/recovery_safety_test.dart`: copia esatta, annullamento, troncamento, alterazione di un byte.
- `test/recovery_safety_gate_test.dart`: archivio sintetico valido, alterazioni del payload, falsificazione manifest/identità allegati.
- `test/disaster_recovery_test.dart`: round-trip e formati storici.
- L'ordine e le transazioni dei vari sidecar **non costituiscono una singola transazione atomica**. Un crash dopo la prima scrittura può lasciare stato misto, anche se l'utente ha una copia esterna verificata.
- Il picker SAF ha bisogno di prove su telefono fisico, soprattutto documenti grandi, permessi, annullamento, riavvio, interruzione e spazio esaurito. Il confronto esatto non dimostra persistenza dell'archivio dopo un guasto hardware.
- **Non** lanciare restore su dati personali non salvati; verificare su fixture sintetiche.

## Gate di accettazione

Flutter format/analyze/test, Android debug/release APK, AAB e Web Preview su commit esatto. Non chiudere l'issue [#75](https://github.com/riccardopinato/Notes-Ecosistema/issues/75) finché journal/rollback cross-store, fault injection, test Android SAF e ripristino dopo crash non sono realizzati e verificati. Non chiudere [#71](https://github.com/riccardopinato/Notes-Ecosistema/issues/71): la produzione richiede un certificato di firma autorizzato e stabile, con prova di aggiornamento dati senza disinstallazione.
