# notes_plus_ai_runtime

Questo modulo Android dynamic-feature ospiterà esclusivamente il runtime
necessario a Needle 3 per Notes Plus:

- JNI wrapper Notes;
- runtime Needle ARM64;
- nessun model weight.

Il runtime resta fuori dal base APK per non imporre alcun costo Needle agli
utenti Free. Le build Android ARM64 di produzione recenti sono circa **1,6 MB**.

## Artifact runtime

Il target è Android ARM64. L'hash/revision esatto del runtime verrà pinnato
nello stesso commit che introdurrà JNI e test real-device: non congeliamo una
build transitoria prima di averne verificato l'ABI.

La feature deve usare delivery **on-demand** e lo stesso entitlement
`PlusFeature.localAi20L` del model pack.

Non materializzare il binario nel repository finché JNI/C API, licenza,
telemetria e test real-device non sono stati chiusi.
