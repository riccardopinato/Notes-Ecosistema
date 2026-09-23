# Notes — Ecosistema 0.25.1

Notes Ecosistema è ora sviluppata in **Flutter**. La linea Kotlin 0.25 è stata congelata nella branch `kotlin-legacy-0.25`.

## Stato corrente

- Versione Flutter: **0.25.1+31**
- Database: compatibilità **Room v8**
- Android: minSdk 26
- CI: format, analyze, test, APK debug, APK release R8 split per ABI
- Sorgente applicazione: `flutter_app/`

## Funzioni principali

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
