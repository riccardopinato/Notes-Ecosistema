# Notes Ecosistema 0.55 — Local Intelligence Foundation

La 0.55 introduce l'infrastruttura per semantic retrieval locale senza rendere l'AI una dipendenza del prodotto.

## Decisione architetturale

Il Core resta deterministico:

- Unified Retrieval continua a funzionare senza modello;
- semantic ranking è opzionale;
- nessun cloud fallback;
- nessun vector DB;
- nessun nuovo oggetto canonico;
- la similarità non crea relazioni esplicite nel Knowledge Graph;
- il modello non è incluso nel base APK.

Quando il provider è disponibile, Notes usa ranking ibrido:

1. retrieval deterministico su testo, metadata, relations, OCR, Study e Documents;
2. embedding locale della query;
3. cosine similarity sugli embedding rigenerabili;
4. fusione deterministica dei due segnali;
5. dedupe sul Note ID canonico.

## Semantic sidecar

`notes-semantic.db` contiene solo:

- model ID + version;
- document ID / Note ID;
- SHA-256 del contenuto indicizzato;
- embedding Float32;
- timestamp.

È completamente rigenerabile e quindi intenzionalmente escluso da:

- Disaster Recovery;
- Open Export;
- Media Bundle;
- sync.

Il purge definitivo di una Note elimina le sue righe semantiche.

## Audit modelli

### Needle 3 — candidato principale

**Ruolo:** ship candidate, non ancora default.

Punti a favore:

- modello singolo ultra-compatto;
- embeddings;
- structured extraction;
- tool calling;
- runtime nativo molto piccolo;
- modello Apache-2.0;
- buona coerenza futura con Smart Capture e Workflow Automations.

Rischi:

- qualità semantic retrieval sulle lingue IT/EN/ES/FR/DE/PT non documentata con un benchmark comparabile;
- sorgenti Cactus pubblicano dimensioni leggermente diverse in base a release/depth;
- binding Flutter corrente richiede validazione reale su ABI e release Needle 3;
- telemetria Cactus/Needle deve essere disabilitata esplicitamente.

**Decisione:** non promuovere Needle finché il benchmark Notes non passa.

### all-MiniLM-L6-v2 qint8

- circa 23 MB per ONNX ARM64;
- embeddings 384d;
- maturo e molto leggero;
- English-oriented.

**Decisione:** controllo inglese, non default prodotto.

### BGE small EN v1.5 int8

- circa 34 MB quantizzato;
- embeddings 384d;
- retrieval specialist;
- English-only.

**Decisione:** controllo retrieval inglese, non default prodotto.

### multilingual-e5-small int8

- 94 lingue;
- riferimento semantic retrieval molto più credibile per il requisito multilingua;
- modello quantizzato circa 118 MB, oltre tokenizer.

**Decisione:** quality reference per benchmark, non pack mobile leggero.

### Altri candidati scartati nel primo audit

- mxbai-embed-xsmall-v1: interessante come footprint, ma English-oriented;
- Granite embedding 30M English: footprint complessivo non competitivo col target;
- POTION base: molto rapido/statico ma English-oriented;
- POTION multilingual: troppo grande;
- EmbeddingGemma: forte copertura multilingua ma classe di dimensione non coerente con il pack leggero.

## Benchmark Notes

La suite iniziale copre IT / EN / ES / FR / DE / PT con intenti:

- viaggio;
- finanza;
- studio;
- progetto;
- benessere;
- documenti/PDF.

Gate di promozione:

- Top-1 >= 78%;
- MRR >= 0.84;
- Top-1 per ogni lingua >= 60%;
- telemetria disabilitata;
- nessun crash/fallback cloud;
- latenza e RAM misurate su device reale prima della promozione.

Il benchmark è eseguibile tramite il provider semantic installato. Senza provider la UI resta sul retrieval deterministico.

## UX

Local Intelligence vive in Impostazioni/Profilo e nel flusso Knowledge Search già esistente.

Non viene aggiunta una nuova sezione principale.

L'utente può:

- abilitare/disabilitare il ranking semantic;
- vedere provider e versione;
- verificare dimensione indice;
- ricostruire l'indice;
- eseguire il benchmark;
- cancellare e rigenerare l'indice;
- consultare l'audit dei modelli.

## Web Preview

La Web Preview 0.55 mostra:

- audit modelli;
- architettura/fallback;
- nessuna falsa simulazione di runtime nativo.

Nel browser il ranking resta deterministico finché non esiste un provider Web esplicitamente validato.

## Non incluso in 0.55.0

- pesi Needle dentro APK;
- download automatico del modello;
- generative chat;
- AI summary;
- AI che crea modifiche senza conferma;
- cloud fallback;
- HNSW/vector DB;
- semantic edge persistenti nel Knowledge Graph.

Il prossimo sub-step può promuovere un **Needle Experimental Pack** solo dopo benchmark reale e integrazione nativa pin/versionata.
