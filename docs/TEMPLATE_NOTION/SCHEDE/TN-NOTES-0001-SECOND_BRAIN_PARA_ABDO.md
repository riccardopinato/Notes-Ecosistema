# TN-NOTES-0001 — Second Brain (PARA Dashboard)

| Campo | Valore |
|---|---|
| Destinazione | **Notes-Ecosistema — principale** |
| Autore / creatore | Abdo Karamallah |
| URL condiviso | https://byabdo.notion.site/Second-Brain-PARA-Dashboard-f258a32233ba4b758b8f47d0ca24f7f6 |
| Scheda pubblica | https://www.notion.com/templates/second-brain-para-dashboard |
| Riferimento centrale | [TPLUX-REF-0001](https://github.com/riccardopinato/Idee-app-Archivi-riferimenti/blob/main/17-RICERCA-TEMPLATE-UX/SCHEDE/TPLUX-REF-0001-SECOND_BRAIN_PARA_ABDO.md) |
| Categoria | Second Brain / PARA / Project & Knowledge Management |
| Stato analisi | **E1 — descrizione e anteprima pubblica** |
| Contenuto interno Notion | **E2 — NON VERIFICATO**: pagina originale non accessibile al connettore |
| Stato prodotto Notes | **RICERCA / PROPOSTA** — nessuna integrazione autorizzata in questa scheda |
| Codice copiato/asset utilizzati | **Nessuno** |
| Rilevazione | 9 novembre 2026 |

## Cosa risulta dalle fonti pubbliche

La scheda del Marketplace presenta un'organizzazione PARA (`Projects`, `Areas`, `Resources`, `Archive`), task e template personalizzabili. L'anteprima pubblica mostra collegamenti di navigazione e azioni rapide, una griglia di aree, schede di progetti con status e indicatori di progresso.

**Attenzione**: non abbiamo verificato i database interni, il funzionamento dei pulsanti, le formule/rollup, le relazioni tra progetti/aree o le versioni effettivamente disponibili nella copia indicata. Gli elementi grafici osservati sono **riferimenti di stile**, non asset da copiare.

## Analisi mirata per Notes

| Pattern osservato | Già presente nel repository Notes | Possibile miglioramento (solo proposta) |
|---|---|---|
| Quick Actions per Task/Project/Area | Capture, Planner e Project Workspace esistenti | Home con scorciatoie contestuali verso i writer canonici |
| PARA: Projects / Areas / Resources / Archive | Knowledge, Research, Project Workspace, raccolte e filtri esistenti | **Viste derivate** di aree/risorse e archivio, senza nuovi store |
| Template personalizzabili | `flutter_app/lib/src/domain/templates.dart`: `PersonalTemplates`, `PageTemplates` | Categoria, anteprima e wizard leggero per scegliere modelli esistenti |
| Progresso delle attività | Planner e Project Workspace; task canonici | Riepilogo calcolato solo su dati reali, non percentuali dimostrative |
| Navigazione compatta e card | Home UI5 e mobile navigation, visual gate #85 ancora aperto | Esplorare layout responsive e accessibilità su Web/Android |
| Progetti con stato | `flutter_app/lib/src/domain/project_workspace.dart` e Planner | Migliorare discoverability, non duplicare Kanban o Project DB |

## Cosa NON fare

- Non importare il sistema Notion come seconda source of truth dell'app.
- Non clonare il layout identico, le formule, le icone, i testi o gli asset del creatore.
- Non aggiungere automaticamente l'architettura PARA come requisito di prodotto.
- Non dichiarare che la Web Preview di Notes abbia tutte queste funzioni: lo Step 1 Web è una persistenza browser con limiti e parità non completa.
- Non avviare la creazione di un nuovo template engine: estendere e testare prima `templates.dart`.

## Opportunità e dipendenze

**Valore prevalente**: elevato come *riferimento di UX* (Quick Actions / gerarchia PARA / schede), non come donor certificato.

**Prima dell'implementazione**: rispettare priorità correnti #46 Smart Inbox, #51 Project Dependencies, #85 UI5; verificare la capacità della persistenza Web e il contratto di importazione/backup. Qualsiasi integrazione richiede proposta tecnica, approvazione, PR e test indipendenti.

**Per Anna's Diary**: soltanto possibili pattern astratti (scorciatoie, card personali), non il sistema PARA completo. Il template **non** occupa una voce nell'indice dei template Anna.

## Prossima verifica E2

- Ottenere un export autorizzato **Markdown & CSV** che includa le sottopagine della stessa copia/variante Notion.
- Enumerare database CSV, proprietà, formule disponibili, relazioni, template di pagina e file media consentiti; annotare ciò che l'export non conserva.
- Acquisire screenshot se servono per una verifica reale del layout e dei casi mobile.
- Aggiornare questa scheda e `CATALOGO.json` mantenendo l'ID, poi confrontare con il codice corrente.

**Origine delle osservazioni**: [catalogo centrale pubblico](https://github.com/riccardopinato/Idee-app-Archivi-riferimenti/blob/main/17-RICERCA-TEMPLATE-UX/SCHEDE/TPLUX-REF-0001-SECOND_BRAIN_PARA_ABDO.md), non ispezione integrale della pagina Notion privata. Nessun dato di acquisto o template commerciale salvato nel repository.

## Aggiornamento 09/11 — Export ricevuto e verificato (E2 parziale)

Esaminato lo ZIP Notion del Second Brain: **42 file, 25 Markdown e 17 CSV**. Esempi nei database: 6 progetti, 4 aree, 4 risorse e 6 task. I CSV contengono proprietà di status, date, priorità e progressi e riferimenti esportati fra record. Questo **verifica la struttura tabellare**, ma non dimostra formule/rollup originali, configurazione dei pulsanti, viste runtime, funzionamento cloud o identità esatta della variante. La descrizione precedente dello stato E1 resta come cronologia: **stato corrente E2_EXPORT_STRUCTURE_VERIFIED, limitatamente a export strutturale**.
