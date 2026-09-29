# Local LLM Runtime 0.56

## Decisione runtime

Notes 0.56.0 introduce un runtime generativo locale reale su Android usando LiteRT-LM 0.17.1.

La release produce due APK:

- **Standard**: mantiene il budget ARM64 da 38 MiB e usa un bridge stub; tutte le funzioni Notes non-LLM restano disponibili.
- **Local AI (ARM64)**: include le librerie native LiteRT-LM e abilita il motore generativo reale.

Il modello non viene incorporato in nessuno dei due APK. L'utente seleziona un file `.litertlm`, che viene copiato nello storage privato dell'app e usato solo sul dispositivo.

Baseline consigliata per il primo ciclo di QA:

- Gemma 3 270M IT;
- backend CPU;
- contesto massimo runtime: 3072 token;
- output massimo predefinito: 384 token.

Il backend GPU non viene abilitato nella baseline 0.56.0. Viene mantenuto fuori dal percorso standard finché i bundle Gemma 3 270M non risultano affidabili sui device target.

## Architettura

### Dart

`LocalLlmPolicy`

- limiti prompt e contesto;
- system instruction;
- composizione Ask this note;
- composizione Ask workspace con massimo 6 fonti.

`LocalLlmService`

- selezione del file `.litertlm`;
- validazione dimensione 32 MiB – 2 GiB;
- copia atomica in Application Support / `local_llm`;
- un solo modello installato alla volta;
- MethodChannel `notes.ecosystem/local_llm`;
- status/load/generate/cancel/unload/delete.

### Android

`MainActivity.kt` ospita il bridge LiteRT-LM:

- `EngineConfig` CPU;
- massimo 4 thread;
- cache dedicata;
- engine inizializzato in executor single-thread fuori dalla UI;
- `ConversationConfig` senza tool calling automatico e senza thinking channels;
- cancellazione attiva;
- unload esplicito;
- file model consentito solo sotto lo storage privato dell'app.

Dipendenza Android pin:

`com.google.ai.edge.litertlm:litertlm-android:0.17.1`

## UX

La sezione Intelligence mostra lo stato LLM locale.

Senza modello:

- l'intera Knowledge Search continua a funzionare;
- Semantic Retrieval continua a funzionare;
- compare il comando “Installa modello”.

Con modello:

- “Chiedi a questa nota” usa titolo, tag e contenuto della nota;
- “Chiedi al workspace” esegue prima Unified Retrieval e passa al modello solo le fonti locali più rilevanti;
- la risposta può essere inserita nella nota;
- “Interrompi” cancella l'inferenza;
- “Rimuovi” scarica il runtime e cancella il file modello.

## Privacy

Il percorso 0.56.0 è local-only:

- nessun prompt inviato a provider cloud;
- nessun cloud fallback;
- nessun modello scaricato automaticamente;
- nessuna indicizzazione LLM inclusa nei backup;
- il modello resta nello storage privato dell'app.

## Limiti

Gemma 3 270M è deliberatamente piccolo. È indicato per:

- Q&A bounded;
- riassunti brevi;
- estrazione semplice;
- trasformazioni di testo;
- risposte RAG su contesto selezionato.

Non va trattato come sostituto di un modello cloud di fascia alta.

## Gate

Prima del merge:

- Dart format;
- Flutter analyze;
- suite test completa;
- test policy prompt/context;
- APK standard debug/release senza LiteRT-LM;
- size gate ARM64 standard invariato a 38 MiB;
- build separata **Local AI ARM64** che compila il bridge Kotlin contro LiteRT-LM 0.17.1;
- regression ceiling dedicato Local AI a 70 MiB, separato dal budget dell'app standard;
- evidence e SHA-256 separati per le due edizioni;
- Web Preview invariata e funzionante.

## Step successivi

0.56.1:

- benchmark real-device;
- streaming token;
- TTFT e token/s;
- memory pressure;
- backend capability matrix.

0.56.2:

- backend adattivo GPU/NPU quando verificato stabile;
- provider alternativo Needle per tool calling/structured extraction;
- eventuale embedding neurale locale tramite runtime reale, mantenendo invariato Unified Retrieval.
