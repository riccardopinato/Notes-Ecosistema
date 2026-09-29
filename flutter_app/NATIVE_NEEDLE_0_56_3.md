# Native Needle Runtime — 0.56.3

## Obiettivo

Attivare realmente Needle 3 20L come provider locale di **Structured
Intelligence** per Notes Plus, mantenendo il Core funzionante senza AI e senza
imporre i 35 MB dei pesi agli utenti Free.

## Packaging definitivo

La 0.56.3 corregge la separazione proposta nella 0.56.2.

- **runtime Needle Android ARM64:** incluso nel base APK perché l'artifact
  pinnato misura solo **1.663.992 byte**;
- **modello Needle 3 20L:** resta nel Play AI pack
  `notes_needle3_20l`, on-demand, circa **35,3 MB**;
- nessun `needle3.cact` può entrare nel base APK;
- il runtime compatto evita la complessità e la fragilità di un secondo
  dynamic-feature module per meno di 2 MB.

Questa scelta segue la regola prodotto corrente: Notes deve restare leggera,
ma non si sacrifica potenza o robustezza per risparmiare pochi MB.

## Artifact pin

Snapshot upstream:

`b274efcb211a9eef48c9a88da4b43bd569696a39`

### Runtime Android ARM64

- file: `android-arm64/libneedle.a`
- bytes: **1.663.992**
- SHA-256:
  `5e0a5daaadca1fbe1c518110bee6bbb1cc97a5e53a16a1e964d0af0186eac60a`

### Modello 20L

- file: `needle3.cact`
- bytes: **35.335.380**
- SHA-256:
  `c9d915eca282ed42d1a09b143b592adb4cc6744ffe2d294adf5cfc5548170c38`

La CI scarica entrambi dagli artifact upstream pinnati e verifica dimensione e
SHA-256. Nessun binario Needle viene committato nel repository.

## Native bridge

`notes_needle_jni` collega il C API Needle con Kotlin:

- `needle_load`;
- `needle_init`;
- `needle_complete`;
- `needle_reset`;
- `needle_last_error`.

L'accesso al runtime è serializzato perché il motore è process-global e non va
usato contemporaneamente da thread diversi.

Il runtime è abilitato solo su **Android ARM64**. Altri ABI mantengono
automaticamente Gemini Nano / deterministic fallback.

## Provider chain

Per i comandi strutturati:

`Needle 3 20L (Plus + pack installato) -> Gemini Nano -> deterministic`

Needle non sostituisce la generazione free-form di `Ask this note` /
`Ask workspace`: il suo ruolo è tool-calling/extraction strutturata.

Gli strumenti consentiti sono soltanto:

- `create_task`;
- `add_tags`;
- `set_priority`;
- `checklist_item`.

L'envelope Needle passa attraverso lo stesso validator della 0.56.1. Un nome
tool sconosciuto, un enum non valido o argomenti malformati vengono scartati.
Il modello produce **proposte**, non applica modifiche direttamente.

## Privacy

- inferenza offline;
- nessun cloud fallback;
- il contenuto della nota non viene inviato a Cactus;
- telemetria disabilitata in build/distribuzione;
- il pack modello viene risolto localmente tramite Play AI Delivery.

## Real-device benchmark

La build debug espone `Test Needle` quando il pack è installato.

Il benchmark misura:

- exact tool match sui 4 tool canonici;
- inference latency;
- delta PSS;
- stabilità di chiamate consecutive.

La CI può certificare compilazione, linking, packaging e fallback, ma **non**
può certificare prestazioni reali del modello perché il runner non è un
telefono Android ARM64 con il Play AI pack installato.

## Size policy

Il precedente limite di 38 MiB non è più un requisito hard.

- **38 MiB:** soft target; superarlo genera warning e richiede revisione;
- model weights nel base APK: errore bloccante;
- crescita estrema/involontaria dell'APK: guardrail tecnico separato;
- qualche MB giustificato da una funzione utile non blocca la release.

## Gate

0.56.3 richiede:

- format/analyze/test PASS;
- runtime Needle scaricato e hash-verificato;
- CMake/JNI ARM64 compile/link PASS;
- APK debug/release PASS;
- base APK privo di `needle3.cact`;
- AAB con AI pack on-demand verificabile;
- Web Preview PASS;
- real-device benchmark disponibile per la certificazione hardware.
