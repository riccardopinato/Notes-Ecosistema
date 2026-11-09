# TN-NOTES-0002 — Book Tracker (Mindful Setups)

**Categoria:** Reading / Knowledge / Collections. **Fonte:** Notion Markdown & CSV export ispezionato, **E2 struttura verificata**. **Stato prodotto:** RICERCA / POSSIBILE TEMPLATE ORIGINALE FUTURO, non integrato.

**Riferimento master:** [TPLUX-REF-0004](https://github.com/riccardopinato/Idee-app-Archivi-riferimenti/blob/main/17-RICERCA-TEMPLATE-UX/SCHEDE/TPLUX-REF-0004-BOOK_TRACKER.md).

## Funzionalità osservate realmente
L'export comprende 61 file (24 MD, 14 CSV, 23 immagini). Dataset Books, Bookshelves, Library e Reading List, con relazioni/schede associate. Campi: titolo, autore, genere, stato, pagine lette/totali, avanzamento, rating, date, formato e libreria. La guida descrive una formula di avanzamento e il pulsante 'Mark as Finished': **la loro configurazione eseguibile non è verificabile tramite CSV**.

## Riuso consigliato per Notes
- Preset **Biblioteca personale** con raccolte e tag canonici, elenco “Da leggere / In lettura / Finito” ed eventuali pagine collegate alle note.
- Informazioni bibliografiche e stato lettura registrati tramite lo schema canonico esistente o nuove proprietà approvate, **senza un secondo database**.
- Indicatori derivati dal conteggio pagine solo quando disponibile e valido; niente percentuali illusorie. Preview e creazione reversibile.
- Prima del codice verificare `flutter_app/lib/src/domain/library.dart`, `templates.dart`, `properties.dart` e `research.dart` alla revisione attuale.

## Licenza: divieto di rivendita del template originale
Il materiale incluso contiene un'esplicita restrizione d'uso personale e di rivendita/redistribuzione senza autorizzazione. **NON** includere ZIP, foto, PNG, copertine, screenshot, testo, formule o template del creatore nel prodotto commerciale. È candidabile **solo un template Flutter originale sviluppato clean-room**.

## Gate
Evidenza dei dati interni E2, test UX/Figma non svolti, build/QA non svolti, approvazione di prodotto da richiedere in fase futura. Nessuna funzionalità implementata in questa PR.
