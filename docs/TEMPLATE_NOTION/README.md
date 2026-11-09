# Template Notion — Notes-Ecosistema

Catalogo **di ricerca** per i template Notion utili a **Notes-Ecosistema**. Le schede sono riferimenti organizzativi, UX e funzionali: **non** significano che il template commerciale sia importato nell'app o che una feature sia stata implementata.

## Indice per Notes

| ID Notes | Template | Categoria | Riferimento centrale | Evidenza | Ammissione prodotto | Scheda |
|---|---|---|---|---|---|---|
| TN-NOTES-0001 | Second Brain (PARA Dashboard), Abdo Karamallah | Second Brain · PARA · knowledge / progetti | TPLUX-REF-0001 | **E2 export strutturale**: 25 MD / 17 CSV; formule runtime non verificate | **PROPOSTA** | [Analisi Notes](SCHEDE/TN-NOTES-0001-SECOND_BRAIN_PARA_ABDO.md) |
| TN-NOTES-0002 | Book Tracker, Mindful Setups | Biblioteca / Knowledge | TPLUX-REF-0004 | **E2 export strutturale**: 61 file; rivendita originale vietata | **PROPOSTA** | [Analisi Notes](SCHEDE/TN-NOTES-0002-BOOK_TRACKER.md) |

Il registro strutturato `CATALOGO.json` replica **solo le associazioni locali a Notes**, non sostituisce l'archivio centrale dei riferimenti e delle capability.

## Metodo di classificazione

- **Destinazione primaria**: catalogare qui solo i template con utilità per note, ricerca, progetti, task, studio, lavagna, Knowledge Graph e produttività. I template principalmente affettivi/personali appartengono al [catalogo Anna's Diary](https://github.com/riccardopinato/Agenda-per-Anna/tree/main/docs/TEMPLATE_NOTION).
- **Template trasversale**: un solo record master nel [catalogo centrale App Factory](https://github.com/riccardopinato/Idee-app-Archivi-riferimenti/tree/main/17-RICERCA-TEMPLATE-UX); le eventuali schede nei due repository motivano separatamente le funzionalità ammissibili per ciascun prodotto. Non si creano due copie dei file commerciali.
- **Livello evidenza**: E0 titolo; E1 pagina pubblica/anteprima; E2 file autorizzato realmente esaminato; E3 solo donor di codice con licenza, file, SHA e test verificati. Un link accessibile non prova formule, proprietà o contenuto interno.
- **Stato prodotto**: RICERCA → PROPOSTA → APPROVATO → IN_CODICE → TESTATO → RELEASE. Non saltare i gate: la presenza della scheda non promuove automaticamente il prodotto.
- **Privacy/licenze**: non archiviare acquisti personali, ricevute, URL di download con token, media o asset proprietari. I pattern si implementano in modo originale.
- **Riuso prima di duplicare**: ricercare owner esistenti (es. `flutter_app/lib/src/domain/templates.dart`, `planner.dart`, `visual_documents.dart`, Project Workspace). Non creare un secondo database, un secondo planner o una nuova CAP senza deduplicazione nel catalogo centrale.

## Come aggiungere un template

1. Leggere il riferimento originale e cercarlo nell'indice prima di assegnare un nuovo ID `TN-NOTES-NNNN`.
2. Usare [MODELLO_SCHEDA.md](MODELLO_SCHEDA.md), indicando fonte, livello di evidenza, funzioni e grafica osservate, limiti, stato e differenza rispetto ai sorgenti reali.
3. Aggiornare **scheda + indice README + `CATALOGO.json`** in una sola PR, conservando gli ID precedenti.
4. Per E2 usare l'esportazione Notion **Markdown & CSV con sottopagine** o un workspace autorizzato; verificare eventuali perdite dell'export e completare con screenshot se necessario.
5. Ammettere funzionalità nel prodotto soltanto dopo approvazione separata, test e valutazione della roadmap corrente.

**Baseline di classificazione**: Notes `main@2780847a0779573ab54d0d68a088e4f552e2840a`, App Factory Core `2b3ae9e01764b7504980efca34f2543949dc7b89` (Master 27 / Golden Index 29). Classificazione documentale 2026-11-09; i commit futuri richiedono nuova verifica per affermazioni di implementazione.

## Idea monetizzazione: Template Store interno

[**TPL-STORE-2026-01 — idea valida da valutare**](https://github.com/riccardopinato/Idee-app-Archivi-riferimenti/blob/main/17-RICERCA-TEMPLATE-UX/IDEA_STORE_TEMPLATE_INTERNO_2026-11-09.md): template **originali** per Notes, acquisto una tantum, prezzo ipotetico **€3,99**, preview, ripristino acquisti e preset gratuiti. **BACKLOG / non implementato**: niente SKU, IAP, nuova schermata né pagamento. Gli export di terzi non sono rivendibili automaticamente.
