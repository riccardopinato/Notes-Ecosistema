# Light Theme Contrast Polish — Notes Ecosistema 0.36.1

## Obiettivo

Correggere i testi bianchi/quasi bianchi che risultavano poco leggibili nel tema chiaro, mantenendo invariata la direzione estetica del dark theme.

## Regole applicate

- headline editoriali su superfici chiare: blu brand `#3559E0`;
- titoli/card text: `onSurface`;
- descrizioni, helper, label secondarie ed empty state: `onSurfaceVariant`;
- titolo di sezione dell'AppBar: blu brand nel tema chiaro;
- bianco riservato alle superfici primary/blu o ad altre superfici scure;
- card primaria Home: eyebrow esplicitamente `onPrimary`;
- dark theme: headline e titoli continuano a usare i colori chiari già previsti dal tema scuro.

## Schermate coperte

La correzione è centralizzata nel tema e quindi si propaga a:

- Home;
- Note;
- Diario;
- Attività / Planner;
- Spazi;
- Cerca;
- sheet e card che usano la tipografia Material condivisa.

## Test

`test/light_theme_contrast_test.dart` verifica:

- headline light = primary;
- title light = onSurface;
- body secondari = onSurfaceVariant;
- nessuna headline light bianca;
- dark theme non viene forzato sul blu;
- EditorialAppTitle è blu nel light theme.

## Release

Versione: `0.36.1+46`.

La modifica è esclusivamente visiva/tematica: nessuna migrazione dati, nessuna modifica a sync, lifecycle o formato backup.
