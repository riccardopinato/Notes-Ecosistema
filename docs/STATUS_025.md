# Notes Ecosistema — stato 0.25.0

Baseline consolidata: 0.24.1 / versionCode 29 / Room v8.

0.25.0 / versionCode 30 integra la Whiteboard + Mind Map foundation senza nuova migrazione Room:
- VisualDocumentKind SKETCH / WHITEBOARD retrocompatibile;
- WhiteboardDocument + codec JSON v1;
- WhiteboardViewModel con autosave debounced/off-main e flush finale;
- canvas infinito, pan/zoom, nodi, edge, penna/evidenziatore/gomma, forme;
- modalità Mind Map, figli e auto-layout;
- routing e filtri Libreria distinti;
- blocco WHITEBOARD nel Universal Block Editor;
- backup, media bundle e GitHub Sync consapevoli del tipo visuale;
- test codec, mind map, metadata e block round-trip.

Room resta v8. La fase successiva prevista è 0.26 Cloud Identity + Shared Spaces, da iniziare solo dopo build CI verde della 0.25.
