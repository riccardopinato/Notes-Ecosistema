# Notes — Home & Navigation UI5 Blueprint (Cantiere B)
**Stato:** DESIGN PROPOSAL · non implementato · non certificato su dispositivo  
**Baseline codice:** `Notes-Ecosistema@abbcab3b59bb67462238ad047fd619935a9acc0b` · Flutter `0.56.3+74`  
**App Factory:** Core `3481a8190a5db5965bb22f84832094268d05be98`, Master v27 / Golden Index v28  
**Confine:** nessuna modifica a `app.dart`, `home_screen.dart`, database, navigator, provider, deep-link, versione, firma o storage in questa PR.  
**Dipendenze:** Smart Inbox #46 (cantiere C) cambia la Home; implementare la Home UI5 solo dopo il suo merge o su file isolati.

## 1. Obiettivo osservabile
La Home attuale include briefing, KPI, creazione note/sketch, progetti, massimo tre suggerimenti Inbox, comparison, Privacy Shield, Study, Knowledge Graph, automazioni, Focus, raccolte. Alcune entry point hanno lo stesso peso grafico nonostante frequenze molto differenti. Scopo: fare emergere il lavoro quotidiano senza nascondere strumenti avanzati o alterare data flow.

### Layout mobile proposto — sopra la piega
```
┌──────────────────────────────────────┐
│ NOTES         Cerca ⌕      +   ⋯    │
│ Sabato 7 novembre                    │
│ Oggi, nel tuo spazio.                │
│                                      │
│ ┌ OGGI ────────────────────────────┐ │
│ │ Agenda · 2 scadenze · 1 Focus   │ │
│ │ [Apri attività]                 │ │
│ └──────────────────────────────────┘ │
│                                      │
│ [ Nuova nota ] [ Nuova attività ]    │
│                                      │
│ CONTINUA                             │
│ [ Ultima nota / progetto corrente ]  │
│                                      │
│ DA RIVEDERE (max 2 · espandi)        │
│ [ Suggerimento con fonte e motivo ]  │
│                                      │
│ Home   Note  Attività  Diario  Spazi │
└──────────────────────────────────────┘
```
Questa è una specifica testuale, **non** uno screenshot dell'app.

### Struttura proposta
1. Header unico: data localizzata, Quick Search, menù operazioni, nuova nota. Nessun duplicato di titolo nella AppBar.
2. Briefing / priorità: una sola card primaria con 3 righe al massimo e CTA chiara.
3. Quick Actions: `Nuova nota` e `Nuova attività` principali; `Disegna`, `Mind Map`, `Voce` nel menu `Crea` esistente.
4. Continua: ultimi elementi autorizzati/non cestinati (lettura derivata dai repository canonici, no secondo store o telemetria).
5. Smart Inbox: mostra al massimo 2 suggerimenti + `Vedi tutti`; conserva source-preview, conferma, i motivi, ACL e Undo del cantiere C. Nessuna scrittura senza gesto esplicito.
6. Moduli avanzati: Studi, Progetti, Knowledge Graph, Automazioni, Privacy Shield, confronto versioni e raccolte in `Strumenti`, raggruppati per scopo; tutti restano raggiungibili.
7. Personalizzazione opzionale CAP-0147: riordino di **soli moduli visuali**, preferenze locali `home_layout_v1` con versione e default sicuri; mai duplicare note o tasks. Non anticipare il codice in questa PR.

## 2. Navigazione proposta
- Mobile: 5 destinazioni persistenti — **Home, Note, Attività, Diario, Spazi**. **Cerca** resta accessibile dall'AppBar e dal Quick Switcher/shortcut; reindirizzamento all'index attuale `_index == 5` senza perdere query, filtri e backstack.
- Tablet/Desktop (>=900 dp): `NavigationRail` esistente con 6 destinazioni incluse Cerca; evitare un secondo navigator parallelo.
- Modalità `Ricerca`: deep link, `Ctrl+K`, `Ctrl+Shift+F`, rientro dall'editor e restore della query devono conservare semantica e ACL.
- Da notifiche, widget, Quick Capture, sync e link esterni: mantenere il comportamento esistente. Nessun reset di sessione/cambio account in routing.
- Feedback errori, empty state e loading: visibili, azionabili, con `Semantics` appropriate.

## 3. Sistema visivo (riuso)
- Colori esistenti: background `#F6F4EF`, primary `#3559E0`, earth `#69574B`, surface `#FFFDFA`. Dark già in `NotesTheme`; nessuna sostituzione brand.
- Gerarchia: headline serif **solo** per hero e principali intestazioni; testo operativo e numeri con Material 3. Verificare l'uso di `fontFamily: serif` su dispositivi, non includere nuovi font senza licenza e controllo peso.
- Scala: spaziature 4/8/12/16/24 dp, CTA principali >=48 dp, icone + etichetta, bordi e radius riusati dal Theme.
- Stati: selezionato, focus, disabled, loading, errore, empty, no-source/ACL sempre distinti; non usare il solo colore come significato.
- Movimento: transizioni leggere solo quando riducono disorientamento, disattivabili per accessibilità; nessuna animazione decorativa permanente.
- Stringhe: tutte e 6 le lingue `en,it,es,fr,de,pt` e formati data locali. Il titolo oggi è ancora hardcoded in italiano nel sorgente.

## 4. Roadmap atomica e confini fra i cantieri
- **B1 (questa PR):** blueprint, mappa IA, criteria e matrici device. Nessuna modifica UI.
- **B2 (post C):** estrarre una configurazione/view model puramente derivata per la Home; widget isolation, test golden screenshot su dataset sintetico.
- **B3:** implementare gruppi `Continua`, `Da rivedere`, `Strumenti` in `home_screen.dart` con feature flag reversibile.
- **B4:** solo in un altro branch modificare `app.dart` per cinque tab mobile; preservare route `_index==5` e tablet Rail a sei, con deep-link widget tests.
- **B5:** tema sistema e CAP-0147 Home riordinabile, localizzazione/QA accessibilità, poi scelta del flag default dopo acceptance.
- Lo Step C #46 possiede i writer, callback e source revisions. B NON li riscrive; solo layout.
- Il cantiere A #72 possiede Flutter/Android CI e toolchain. B NON tocca i workflow.
- Il cantiere D possiede il rapporto CAP, non assume che questo blueprint sia una CAP integrata.

## 5. Acceptance UI/device
| Gate | Matrice | Stato |
| --- | --- | --- |
| UI snapshots | 320/360/393/600/900/1280 dp, light/dark, empty/20/500 notes | DA ESEGUIRE |
| Leggibilità | textScale 1, 1.3, 2.0, landscape, tastiera aperta | DA ESEGUIRE |
| Accessibility | TalkBack, keyboard focus, 48 dp targets, semantic labels, no color-only | DA ESEGUIRE |
| Navigazione | ogni sezione, ricerca, Ctrl+K, backstack, deep link, cold start | DA ESEGUIRE |
| Security / state | account switch, Shared Spaces ACL, 3 Inbox max, no stale write | DA ESEGUIRE |
| Performance | 500/5000 notes: jank p95, frame time, memory, no unbounded build | DA ESEGUIRE |
| Regression | editor, Focus, attachments, backup, Web parity, dark theme | DA ESEGUIRE |

**Decision gate:** document approval/design review first; production UI only after screenshot/device evidence and exact-head CI. The existing Kotlin-era `docs/RESTYLING_0120.md` is historical, not the Flutter blueprint. No APK, screenshot, runtime or accessibility certification is claimed here.
