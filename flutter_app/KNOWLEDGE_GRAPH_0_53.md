# Notes Ecosistema 0.53 — Knowledge Graph

Knowledge Graph è una **proiezione derivata** dei sistemi già canonici. Non introduce database, entità persistenti o sync dedicati.

## Sorgenti

- Note e Task dal Core;
- internal link Markdown legacy e stable link `notes://object/<id>`;
- relazioni esplicite da Knowledge Store;
- Project Workspace e membership note/task;
- LearningItem di Study collegati alla source note;
- PDF del Document Workspace, inclusi asset referenziati e annotazioni.

## Modello

Nodi:
- Note;
- Task;
- Project;
- Study;
- PDF.

Archi:
- Link;
- Relazione;
- Nel progetto;
- Studia da;
- Documento.

Il grafo viene ricostruito dai dati correnti. Eliminare il grafo non elimina nessun contenuto perché non esiste una source of truth separata.

## UX

- pan e zoom;
- ricerca nodo;
- focus 1-hop / 2-hop / tutto;
- filtri per tipo di arco;
- layout deterministico e bounded;
- doppio tap per aprire l'oggetto sorgente;
- permessi Shared Spaces rispettati in apertura;
- accesso da Home, Quick Switcher e shortcut desktop `Ctrl+Shift+G`.

## Vincoli

- nessun Graph DB;
- nessun embedding/vector store richiesto;
- nessuna AI;
- nessun duplicato di Note/Task/Project/Study/Document;
- nessun CRDT aggiuntivo;
- massimo 120 nodi renderizzati per proiezione standard per evitare degrado UI.

## Gate

Format, analyze, test, APK debug/release, size gate, Evidence Bundle e Web Preview restano i gate standard.
