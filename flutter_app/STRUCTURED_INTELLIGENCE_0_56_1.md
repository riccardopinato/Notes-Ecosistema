# Structured Local Intelligence 0.56.1

## Obiettivo

Introdurre un livello di structured intelligence locale riusabile senza aggiungere modelli pesanti a Notes e senza trasformare l'AI in requisito del Core.

La 0.56.1 separa tre responsabilità:

1. provider generativo locale;
2. schema e validazione dei comandi;
3. applicazione delle azioni da parte delle feature canoniche.

Il terzo punto resta intenzionalmente fuori dal motore: questa release produce suggerimenti, non esegue modifiche automatiche.

## Comandi ammessi

Il contratto supporta esclusivamente:

- `create_task`;
- `add_tags`;
- `set_priority`;
- `checklist_item`.

Ogni payload è bounded e validato. I comandi sconosciuti vengono scartati.

## Provider chain

### Gemini Nano

Quando Android AICore espone Gemini Nano come disponibile:

- Notes costruisce un prompt JSON-only;
- il modello riceve solo titolo e corpo bounded della nota;
- il risultato viene parsato e validato localmente;
- testo extra, fence Markdown e JSON parzialmente avvolto vengono normalizzati in modo difensivo;
- comandi non consentiti non attraversano il validator.

### Fallback deterministico

Se Gemini Nano non è disponibile o la risposta non è valida:

- checkbox Markdown non completate diventano suggerimenti task;
- liste esplicite diventano suggerimenti checklist;
- hashtag espliciti diventano suggerimenti tag;
- non vengono inferite scadenze o priorità.

Il fallback mantiene il valore del feature set anche sui device privi di AICore.

## Safety e data integrity

- nessuna eliminazione;
- nessun invio;
- nessun acquisto;
- nessuna chiamata di rete;
- nessuna modifica automatica a Note, Task o Planner;
- nessun nuovo sidecar o source of truth;
- nessun dato generato entra nel backup finché l'utente non lo accetta attraverso una superficie canonica.

## Needle 3

Needle 3 non è incluso nella 0.56.1.

Il contratto è stato progettato per permettere a un provider tiny dedicato di sostituire la fase di produzione JSON senza modificare validator, fallback o feature consumer.

Prima dell'integrazione nativa vanno verificati separatamente:

- JNI/static library Android;
- modalità di distribuzione del runtime;
- licenza e redistribuzione dei pesi;
- telemetria disabilitabile/offline;
- RAM e latenza sui device reali;
- qualità 4L/8L/20L sui tool schema Notes;
- impatto su APK e storage post-install.

## Gate

- Dart format;
- Flutter analyze;
- suite test completa;
- regressioni parser/validator/fallback;
- APK debug/release;
- ARM64 <= 38 MiB;
- Web Preview invariata;
- zero nuovi model weights bundled.
