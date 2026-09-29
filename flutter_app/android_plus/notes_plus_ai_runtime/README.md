# notes_plus_ai_runtime

Questo modulo Android dynamic-feature ospiterà esclusivamente il runtime
necessario a Needle 3 per Notes Plus:

- JNI wrapper Notes;
- runtime Needle ARM64;
- nessun model weight.

Il runtime non deve essere collegato staticamente al base APK, perché
l'artifact `libneedle.a` ARM64 corrente misura 12.121.380 byte e farebbe
saltare inutilmente il budget dell'app per gli utenti Free.

## Artifact runtime pinnato

- SHA-256:
  `e11d0a4ac455a4a5d9d3ed7fcd29fb0d7adc7d8832b1e1511c2b22b173cfb133`
- bytes: `12121380`
- target: Android ARM64.

La feature deve usare delivery **on-demand** e lo stesso entitlement
`PlusFeature.localAi20L` del model pack.

Non materializzare il binario nel repository finché JNI/C API, licenza,
telemetria e test real-device non sono stati chiusi.
