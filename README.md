# Notes — Ecosistema 0.26.0

Notes Ecosistema è ora sviluppata in **Flutter**. La linea Kotlin 0.25 è stata congelata nella branch `kotlin-legacy-0.25`.

## Stato corrente

- Versione Flutter: **0.26.0+32**
- Database: compatibilità **Room v8**
- Android: minSdk 26
- CI: format, analyze, test, APK debug, APK release R8 split per ABI
- Sorgente applicazione: `flutter_app/`

## Shared Spaces 0.26

- Spazi collaborativi **selettivi**: tutto resta privato finché non viene aggiunto esplicitamente a uno spazio.
- Ruoli Proprietario, Editor e Viewer con apertura read-only per i Viewer.
- Inviti `NS26` a scadenza, senza password o token incorporati.
- Note, attività, Sketch e Whiteboard possono entrare o uscire da uno spazio senza duplicare o cancellare il contenuto personale.
- Pacchetti ZIP di aggiornamento verificati: metadati dello spazio, documenti e soli allegati referenziati.
- Merge non distruttivo: le versioni locali più recenti vengono conservate e i conflitti equivalenti generano una copia separata.
- Room resta **v8**: i metadati di collaborazione sono separati dal database canonico.

La 0.26 introduce il **core collaborativo portabile/offline**. Il trasporto cloud automatico e real-time multi-account non è ancora incluso in questa release; i pacchetti Shared Space sono il meccanismo di scambio della 0.26.0.


- Note Markdown, checklist, tag, raccolte, preferiti, pin, archivio e cestino.
- Universal Block Editor.
- Planner Pro: Agenda, Giorno, Settimana, Mese e Kanban.
- Focus/Pomodoro persistente e statistiche settimanali.
- Diario giornaliero.
- Sketchbook multipagina.
- Whiteboard e Mind Map.
- Smart Capture con scanner documenti, OCR e Web Capture.
- Allegati immagini, audio e documenti con storage SHA-256.
- Quick Capture Android, scorciatoie, widget Home e share target.
- Promemoria Android con apertura e snooze.
- GitHub Sync con allegati e tile Quick Settings.
- Backup JSON v6 compatibile con la linea Kotlin.
- Backup ZIP completo con allegati e restore verificato.
- Export e condivisione PNG di Sketch e Whiteboard.
- Knowledge tools, template e ricerche salvate.

## Build

```bash
cd flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

La CI GitHub produce automaticamente anche gli artifact APK.

## Compatibilità e migrazione

La migrazione Flutter conserva il formato dati della versione Kotlin, incluso il database Room v8 e il backup JSON v6. Gli allegati mantengono chiavi content-addressed SHA-256.

Il rapporto di parità 0.25.1 è in `flutter_app/PARITY_0_25_1.md`.

## Linea Kotlin storica

Il sorgente Kotlin completo precedente alla promozione Flutter è preservato in:

`kotlin-legacy-0.25`

Non usare quella branch per il nuovo sviluppo.

## Roadmap

Il prossimo ciclo funzionale è **0.26 — Shared Spaces**: spazi collaborativi selettivi per note, attività ed eventi condivisi, mantenendo privato per default il resto del workspace.
