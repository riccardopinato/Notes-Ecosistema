# Step 4 · Smart Inbox #46: compensazione di race in cantiere QA

Questa PR si applica al **solo percorso sperimentale** di collegamento Note → Project Workspace, già protetto in `app.dart` da `kDebugMode && NOTES_QA_SMART_INBOX_PROJECT_LINK` default FALSE. Nessun percorso production è stato attivato.

## Incremento
- Ogni inserimento tramite writer canonico `ProjectStore.attachIfAbsentForSmartInbox` restituisce il receipt creato.
- Dopo l'await della transazione, si rilegge Note persisted + lista canonica, identità / membership Shared Spaces, scope di connessione GitHub, progetto privato attivo e **receipt esatto del link**.
- Se una fonte diventa shared, cambiano account/token/revisione, il link o i permessi durante la scrittura, `SmartInboxProjectCommitGuard` tenta una **compensazione condizionale** con `ProjectStore.detachIfUnchanged`, quindi rifiuta la conferma; se Undo non è verificabile ritorna errore bloccante.
- Test deterministici iniettano cambio ruolo, errore di lettura, fail Undo, writer no-op/errore, e receipt invariato.

**Limite fondamentale:** revalidare dopo un commit **non serializza tre database diversi**; resta una finestra fra ultima lettura e ritorno, perciò la race cross-store NON è chiusa. #46 resta OPEN e la capability non è production-ready. Prima di abilitare serve un unico coordinator/lock transazionale che copra tutte le vie di modifica Note, Shared Spaces, Project; kill-process, account switch e fault injection integrati su storage reali. Nessuna promozione CAP-0148.
