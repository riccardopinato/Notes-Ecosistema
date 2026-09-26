# Universal Properties & Adaptive Editor — Notes Ecosistema 0.33.0

## Obiettivo

La 0.33 apre P1 senza rompere la baseline 0.32:

1. aggiunge proprietà strutturate riutilizzabili;
2. introduce graceful degradation dell'editor;
3. conserva `notes.db` v8 come sorgente legacy compatibile;
4. evita che metadati e performance hardening diventino un secondo editor.

## Universal Properties

Tipi iniziali:

- text;
- number;
- date;
- select;
- multi-select;
- checkbox;
- status.

Le definizioni sono workspace-wide e hanno ID stabile, nome, tipo e opzioni.
I valori appartengono a una nota tramite `noteId + definitionId`.

### Persistenza sidecar

Le proprietà vivono in:

`notes-metadata.db`

Tabelle:

- `property_definitions`;
- `property_values`.

Motivo: non alterare la struttura `notes.db` v8 e non compromettere la
compatibilità della linea dati legacy. Il sidecar usa SQLite/sqflite e foreign
key interne fra definizioni e valori.

L'eliminazione definitiva di una nota elimina anche i relativi valori sidecar.
Il soft-delete mantiene i valori perché il ripristino deve essere lossless.

## Adaptive Editor

Il contenuto Markdown resta canonico. `content_blocks` resta un derivato
ricostruibile.

Profili:

### Completo

Per documenti normali.

- draft debounce 280 ms;
- parsing blocchi live;
- knowledge tools live;
- preview on-demand.

### Leggero

Scatta oltre 64 KiB oppure 600 righe.

- draft debounce 650 ms;
- niente reparse dei blocchi a ogni carattere;
- knowledge tools live sospesi;
- i blocchi vengono ricostruiti solo quando richiesti.

### Essenziale

Scatta oltre 192 KiB oppure 1800 righe.

- draft debounce 1200 ms;
- parsing blocchi live sospeso;
- modalità Blocchi sospesa;
- preview Markdown costosa sospesa;
- testo e salvataggio restano sempre disponibili.

Il principio è:

> la complessità può ridurre gli effetti live, mai l'affidabilità dell'editing.

## Invarianti

- nessuna proprietà può cambiare il body Markdown;
- nessuna degradazione può impedire il salvataggio;
- i content block non sono mai più autorevoli del Markdown;
- proprietà invalide vengono rifiutate prima della persistenza;
- opzioni select/status sono canoniche e case-insensitive in input;
- il purge definitivo pulisce i valori della nota;
- nessuna migrazione distruttiva di `notes.db`.

## Limiti intenzionali 0.33

Questa è una foundation.

La 0.33 non implementa ancora:

- viste database universali;
- relations;
- rollups;
- proprietà condivise via GitHub Sync;
- export/import delle proprietà;
- filtri avanzati per proprietà.

Questi punti vengono completati nelle fasi P2/P3, riusando questo modello.

## Test

Test automatici dedicati:

`test/properties_adaptive_test.dart`

Coprono:

- normalizzazione typed values;
- contratti definition/options;
- profilo editor normale;
- degradazione su note grandi.

Il checkpoint FULL deve inoltre continuare a eseguire l'intera suite Flutter,
analyze, build debug/release, size gate ed Evidence Bundle.
