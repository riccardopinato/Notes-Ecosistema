# Daily Work & Capture — Notes Ecosistema 0.34.0

## Obiettivo

La 0.34 rende **Oggi** il punto di aggregazione operativo dell'ecosistema senza
creare una nuova entità o duplicare dati.

Il briefing legge esclusivamente oggetti canonici già presenti:

- TaskDetails / Planner Pro;
- scadenze e pianificazione;
- note Inbox senza raccolta;
- Shared Spaces unread/activity.

## Daily Work Briefing

La Home mostra in modo deterministico:

- blocchi pianificati oggi, ordinati per ora;
- task in scadenza oggi;
- task arretrati;
- novità non lette nei workspace;
- Inbox da smistare.

Toccare un elemento riapre il sistema originale: Planner o editor nota.
Nessun record "Today" viene salvato.

## Quick Switcher

Ricerca locale su:

- note;
- attività;
- raccolte;
- comandi Oggi / Nuova nota / Attività / Cerca.

Il ranking favorisce match esatti, prefissi e poi contenimenti.

## Inbox / Triage

Inbox non è una nuova tabella: una nota personale attiva senza raccolta è
considerata non smistata. Il briefing mostra gli elementi più recenti e
l'editor esistente permette di assegnare raccolta e tag.

## Task avanzati

TaskDetails aggiunge `subtasks` in modo backward-compatible nel JSON
esistente. Ogni sotto-attività ha:

- ID stabile;
- titolo;
- stato completato.

Le vecchie attività senza campo `subtasks` continuano a essere valide.

## Focus Editor

È una modalità dello stesso EditorScreen, non un editor parallelo.

Quando attiva nasconde controlli secondari e lascia prioritari:

- titolo;
- testo;
- autosave/draft;
- salvataggio;
- uscita da Focus.

## Voice Capture

La voce "Nota vocale" riusa il recorder già validato nell'editor.

Flusso:

`nuova nota -> registrazione audio originale -> AttachmentStore SHA-256 -> nota`

L'audio originale non viene sostituito da trascrizioni. Eventuali trascrizioni,
riassunti o task estratti appartengono alla fase Intelligence e devono restare
derivati separati.

## Invarianti

- Oggi è una vista, non una nuova entità;
- Inbox è una classificazione derivata, non un secondo archivio;
- Quick Switcher non duplica la ricerca completa;
- subtasks restano nello stesso TaskDetails;
- Focus Editor non cambia formato dati;
- Voice Capture preserva sempre l'audio originale;
- P2 funziona completamente senza AI.

## Test

`test/workday_quick_switcher_test.dart` copre:

- aggregazione briefing;
- ordinamento blocchi;
- scadenze/arretrati;
- Inbox;
- Shared unread;
- ranking Quick Switcher;
- compatibilità subtasks.

Il checkpoint FULL continua a includere suite completa, analyze, build
debug/release, size gate ed Evidence Bundle.
