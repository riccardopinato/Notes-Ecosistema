# Optional Intelligence — Notes Ecosistema 0.36.0

## Obiettivo

La 0.36 completa P4 senza rendere l'intelligenza una dipendenza del prodotto.

Regola:

`CORE APP != AI`

Note, editor, Planner, Daily Briefing, capture, ricerca classica, Shared Spaces,
backup, export, Research Workspace e Markdown restano pienamente utilizzabili
senza rete, account o provider AI.

## Knowledge Search locale

`LocalKnowledgeRetrieval` fornisce un fallback deterministico e offline:

- tokenizzazione locale;
- normalizzazione/stemming leggero;
- ranking cosine su vettori di termini;
- estratti dalla nota originale;
- riferimenti espliciti alla nota sorgente.

Non viene presentato come modello embedding o come generazione semantica
onnisciente: è retrieval locale trasparente.

“Chiedi alle mie note” in questa baseline restituisce **fonti rilevanti**.
Non inventa una risposta quando non trova evidenza.

## Related Notes

Lo stesso motore confronta la nota aperta con le altre note personali e propone
documenti correlati, escludendo:

- la nota stessa;
- cestino;
- archivio;
- task;
- documenti visuali.

## Originale → Derivato

Ogni elaborazione vive in:

`notes-derivatives.db`

e punta alla sorgente tramite `sourceNoteId` e fingerprint.

Tipi:

- transcript;
- cleanedTranscript;
- summary;
- extractedTasks.

L'originale non viene mai sovrascritto.

Per Voice Capture:

`audio originale -> transcript grezzo -> transcript pulito -> summary/task`

Audio e corpo nota restano indipendenti dai derivati.

## Elaborazioni locali

### Transcript cleanup

Normalizza spazi e punteggiatura senza sostituire la sorgente.

### Summary

Riassunto estrattivo: seleziona frasi già presenti nel testo in base alla
frequenza informativa. Non genera fatti nuovi.

### Task extraction

Riconosce solo marker espliciti, ad esempio:

- `- [ ] task`;
- `TODO: task`;
- `azione: task`;
- `da fare: task`.

Nessuna frase normale viene convertita automaticamente in task.

## Provider futuri

L'interfaccia `KnowledgeRetrievalEngine` permette in futuro un provider
embedding/LLM, ma ogni provider dovrà:

- essere opzionale;
- essere sostituibile;
- dichiarare rete/costi/privacy;
- citare fonti;
- avere fallback locale;
- scrivere solo derivati;
- non diventare requisito per accedere ai dati.

## Lifecycle

Il purge definitivo di una nota elimina anche i suoi derivati.

Eliminare un derivato non elimina né modifica la nota, l'audio o altre fonti.

## Test

`test/intelligence_derivatives_test.dart` copre:

- ranking locale con citazioni;
- related notes;
- immutabilità dell'input durante cleanup;
- summary bounded/estrattivo;
- task extraction esplicita;
- separazione metadata derivato/sorgente.

La roadmap P0–P4 è funzionalmente completa solo dopo FULL verde della 0.36.
La certificazione hardware resta un gate separato.
