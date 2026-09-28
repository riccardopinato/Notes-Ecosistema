# Local Intelligence 0.55

## Scopo

La 0.55 introduce retrieval semantico locale senza trasformare Notes in un'app dipendente da AI o rete.

La source of truth resta invariata: Note, Task, OCR, Study, PDF, Properties, Research e Relations continuano a vivere nei rispettivi store canonici. L'indice semantico è sempre un derivato eliminabile e ricostruibile.

## Engine 0.55.0

`LocalHashEmbeddingEngine` produce vettori normalizzati fixed-size da 192 dimensioni.

Caratteristiche:

- deterministico;
- completamente offline;
- nessun modello scaricato;
- nessun aumento importante dell'APK;
- token, stemming leggero, subword trigram e alias concettuali multilingua;
- dimensione grezza del vettore: 192 × 4 byte = 768 byte per documento.

Non è un transformer neurale e non pretende equivalenza con modelli embedding server-side. Il contratto `SemanticEmbeddingEngine` permette di sostituirlo in futuro con un modello neurale on-device mantenendo invariati indice, lifecycle e Unified Retrieval.

## Persistenza

Sidecar: `notes-semantic.db`.

Tabella derivata:

- documentId;
- noteId;
- kind;
- fingerprint;
- engine;
- dimensions;
- vector BLOB;
- updatedAt.

L'indice non entra in Disaster Recovery, Media Bundle o Open Export perché può essere rigenerato integralmente dai dati canonici.

## Indicizzazione incrementale

Ad ogni ricerca semantica:

1. Unified Retrieval costruisce i documenti canonici correnti.
2. Ogni documento riceve un fingerprint SHA-256 che include engine, dimensione, identità e contenuto.
3. I record invariati non vengono ricalcolati.
4. I documenti modificati vengono re-embedded.
5. I documenti non più presenti vengono eliminati dall'indice.

Il purge definitivo di una nota elimina anche immediatamente tutti i suoi vettori.

## Ranking

Il retrieval classico resta sempre disponibile.

Con Semantic Search attiva:

- ranking classico = title/tag/text/recency/kind;
- ranking semantico = cosine similarity sul vettore locale;
- fusione = Reciprocal Rank Fusion con peso semantico bounded;
- deduplica finale per noteId.

Se il sidecar o l'engine falliscono, la ricerca restituisce automaticamente i risultati classici invece di fallire.

## Privacy

- nessuna richiesta di rete;
- nessun testo inviato a provider esterni;
- nessun account richiesto;
- indice locale eliminabile dall'utente disattivando la funzione;
- funzione attiva di default ma disattivabile in Impostazioni.

## Web Preview

La Web Preview usa lo stesso `LocalHashEmbeddingEngine` in memoria e fonde ranking classico + vettoriale. Non persiste SQLite nel browser: serve a verificare comportamento e UI, non la persistenza Android.

## Gate 0.55.0

Prima del merge:

- Dart format;
- Flutter analyze;
- suite test completa;
- test determinismo e normalizzazione embedding;
- test sinonimi/concept alias;
- test cross-language;
- benchmark 1.000 embedding;
- build debug APK;
- build release split ABI;
- size gate;
- Evidence Bundle;
- Web Preview build.

## Fuori scope

- generazione testuale;
- LLM locale;
- download automatico di modelli;
- cloud embeddings;
- vector database esterno;
- background indexing continuo;
- modifica delle source of truth.
