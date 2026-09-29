# Adaptive Local Intelligence 0.56

## Obiettivo

Notes deve restare leggera. La 0.56 non incorpora un modello generativo da centinaia di MB e non richiede un download LLM proprietario dentro lo storage dell'app.

Il percorso generativo è adattivo:

1. **Gemini Nano tramite Android AICore / ML Kit Prompt API**, quando disponibile sul dispositivo.
2. **Semantic Retrieval 0.55** come fallback sempre disponibile.
3. **Needle 3** resta il provider nativo ultraleggero candidato per 0.56.1, soprattutto per tool-calling, extraction e routing.

Non esiste alcun cloud fallback automatico.

## Provider primario: Gemini Nano / AICore

Dipendenza client:

`com.google.mlkit:genai-prompt:1.0.0-beta4`

Il modello è gestito da Android AICore. Non viene inserito nell'APK di Notes e non viene copiato nello storage privato dell'app.

Status runtime esposti:

- `AVAILABLE`: generazione locale attiva;
- `DOWNLOADABLE`: il telefono supporta Gemini Nano ma Android deve preparare il modello;
- `DOWNLOADING`: preparazione in corso;
- `UNAVAILABLE`: il device non è compatibile o AICore non è pronto.

La UI mostra sempre lo stato reale prima di esporre i comandi generativi.

## Compatibilità

Prompt API richiede Android API 26+.

La disponibilità effettiva dipende dal dispositivo e dalla configurazione AICore. Notes non presume mai che Gemini Nano sia presente.

Su device non compatibili:

- Search/Quick Switcher/Knowledge Graph semantic-aware continuano a funzionare;
- Related Notes continua a funzionare;
- Ask Note/Workspace generativo viene nascosto;
- nessun errore core impedisce l'uso dell'app.

## Ask this note

Il prompt include solo:

- domanda;
- titolo;
- tag;
- contenuto bounded della nota.

Il contesto della nota è limitato a 10.000 caratteri prima dell'invio ad AICore.

## Ask workspace

Pipeline:

1. domanda utente;
2. Unified Retrieval locale;
3. massimo 5 fonti rilevanti;
4. contesto workspace bounded a 12.000 caratteri;
5. generazione Gemini Nano locale;
6. risposta opzionalmente inseribile nella nota.

Il modello riceve esclusivamente le fonti locali selezionate.

## Privacy

- nessun contenuto inviato a provider cloud;
- nessun endpoint remoto configurato;
- nessun fallback cloud;
- il modello Gemini Nano è gestito dal sistema Android;
- Semantic Retrieval rimane locale;
- la risposta generativa è salvata solo se l'utente la inserisce nella nota.

## Peso applicazione

La 0.56 mantiene un unico APK standard.

Il size gate ARM64 resta invariato:

`38 MiB`

Non esiste più la variante LiteRT-LM/Gemma 3 da ~57 MiB e non viene consigliato alcun modello esterno da ~300 MB.

## Download AICore

ML Kit Prompt API 1.0.0-beta4 ha un problema noto con `download()` quando il progetto risolve `kotlinx-coroutines` 1.10.x o precedenti.

La CI pinna:

`org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0`

per evitare quella incompatibilità.

## Needle 3

Needle 3 è stato valutato come fallback ultraleggero:

- engine Android sotto 1 MB;
- pesi laddered circa 8–29 MB;
- target ufficiale android-arm64;
- inference offline;
- specializzazione forte su tool-calling, extraction, classification ed embedding.

Non viene usato come chatbot generalista perché sacrifica intenzionalmente la capacità di free-form chat.

Il provider Needle viene separato nella 0.56.1 così da poter validare:

- JNI/static library Android;
- licenza e redistribuzione;
- depth ottimale;
- RAM e latenza real-device;
- qualità su tool schema Notes;
- eventuale modello fine-tuned per Notes.

## Gate 0.56.0

Prima del merge:

- Dart format;
- Flutter analyze;
- suite test completa;
- test policy prompt/context;
- compilazione Kotlin del bridge Gemini Nano;
- APK debug;
- APK release split ABI;
- ARM64 <= 38 MiB;
- Evidence Bundle + SHA-256;
- Web Preview PASS;
- nessuna dipendenza LiteRT-LM o modello generativo bundled.

## Step successivo

0.56.1 — Needle Structured Intelligence:

- tool routing locale;
- extraction di task/action item;
- classification/tag suggestion;
- structured note commands;
- benchmark 4L/8L/20L;
- fallback chain Gemini Nano → Needle → Semantic Retrieval.
