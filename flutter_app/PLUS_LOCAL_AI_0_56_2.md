# Notes Plus Local AI — 0.56.2

## Decisione prodotto

Needle 3 20L viene trattato come **Local AI Pack di Notes Plus**, non come
dipendenza del Core e non come peso obbligatorio dell'app.

La versione Free resta pienamente utilizzabile senza Needle. Il pacchetto Plus
aggiunge elaborazione strutturata on-device e deve essere installabile e
rimovibile separatamente.

## Packaging

La distribuzione Android usa due componenti on-demand separati:

1. **AI pack `notes_needle3_20l`**: contiene esclusivamente
   `needle3.cact`.
2. **feature module `notes_plus_ai_runtime`**: contiene JNI/wrapper e runtime
   nativo Needle per ARM64.

Questa separazione è necessaria perché Play AI packs accettano modelli ma non
Java/Kotlin o librerie native. Il runtime non deve finire nel base APK.

Il size gate dell'APK ARM64 base resta **38 MiB**.

## Artifact pin

Modello valutato per questa release:

- modello: Needle 3 20L;
- file: `needle3.cact`;
- upstream revision:
  `3e8e2a66057a29694052d915128b91b53e7e5ead`;
- SHA-256:
  `c9d915eca282ed42d1a09b143b592adb4cc6744ffe2d294adf5cfc5548170c38`;
- dimensione upstream mostrata: circa **35,3 MB**.

Runtime Android ARM64 osservato nella stessa linea di produzione:

- file: `libneedle.a`;
- bytes: **12.121.380**;
- SHA-256:
  `e11d0a4ac455a4a5d9d3ed7fcd29fb0d7adc7d8832b1e1511c2b22b173cfb133`.

Perciò il costo raw complessivo modello + runtime è oggi più vicino a
**47–50 MB** che a 30 MB. Il download effettivo da Play può differire per
compressione e patching.

## Entitlement

0.56.2 introduce un confine esplicito `NotesPlan.free / NotesPlan.plus`.

- release: Plus resta chiuso finché non è collegato il billing reale;
- debug: Plus può essere abilitato internamente per QA;
- nessun toggle utente simula un acquisto;
- il futuro adapter RevenueCat/Play Billing sostituirà il provider
  dell'entitlement senza cambiare il dominio AI.

## Play AI Delivery

Il bridge `LocalAiPackBridge` espone:

- status;
- download;
- cancel;
- remove;
- path del modello solo quando il pack è realmente installato.

La posizione del pack non viene persistita tra i lanci: viene sempre
ri-risolta da Google Play.

Il repository non contiene il binario `needle3.cact`. Il template
`android_plus/notes_needle3_20l` definisce identità e delivery mode; la
pipeline Play definitiva deve materializzare esclusivamente l'artifact
pinnato e verificarne SHA-256 prima del bundle.

## Runtime Needle

La 0.56.2 prepara la delivery ma **non dichiara completata l'inferenza Needle**.

Prima di promuovere il runtime a provider attivo servono:

- JNI/C API verificata contro l'artifact Android ARM64 pinnato;
- telemetria Needle disabilitata;
- zero rete durante inferenza;
- verifica RAM e latenza real-device;
- exact tool match e argument accuracy sul dataset Notes;
- fallback senza crash a Gemini Nano / deterministic engine;
- feature module on-demand verificato con Play Internal Testing.

## Provider contract

Il parser Structured Intelligence ora è multi-provider e ammette la source
`needle`, mantenendo gli stessi validator 0.56.1.

Il modello non può applicare direttamente modifiche. La catena resta:

`provider -> StructuredAnalysis -> validator -> proposta UI -> conferma utente`.

## Gate 0.56.2

- Dart format;
- Flutter analyze;
- suite test;
- Kotlin compile del Play AI Delivery bridge;
- debug/release APK;
- ARM64 base <= 38 MiB;
- Web Preview PASS;
- nessun peso Needle nel base APK;
- nessun entitlement Plus fittizio in release.
