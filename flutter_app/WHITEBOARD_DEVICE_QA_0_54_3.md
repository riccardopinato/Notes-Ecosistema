# Whiteboard Device QA — 0.54.3

Questa checklist separa il gate FULL automatizzato dalla certificazione hardware reale della Whiteboard/Mind Map.

## Baseline automatizzata

Prima del merge devono risultare PASS:

- Dart format;
- Flutter analyze;
- suite test completa;
- build APK debug;
- build APK release split-per-ABI;
- size gate;
- Evidence Bundle;
- build Web Preview;
- stress codec con 20.000 punti;
- validazione WhiteboardRules al ceiling di 50.000 punti;
- regressioni widget per centratura, zoom 2x, Undo/Redo, stylus, canvas profonda, lasso, duplicazione, resize, snap e mini-map.

## Real-device — smartphone

Verificare almeno una volta su Android reale:

- apertura sempre centrata;
- pan e pinch-zoom a 0.2x, 1x, 2x e 3.2x;
- drag post-it a zoom basso e alto;
- Undo/Redo dopo ink, drag, resize, duplicate e delete;
- lasso con dito;
- snap griglia;
- mini-map leggibile senza coprire elementi critici;
- salvataggio e riapertura senza variazioni di posizione;
- export PNG su canvas piccola e molto estesa.

## Real-device — tablet/stylus

Verificare su tablet con penna, se disponibile:

- stylus disegna mentre il dito resta disponibile per navigazione quando configurato;
- nessun tratto spurio durante appoggio del palmo;
- pressione produce variazione visibile e controllabile;
- evidenziatore mantiene colore/spessore durante anteprima e tratto finale;
- pinch con dita non interrompe o duplica il tratto stylus;
- passaggio Penna -> Seleziona -> Naviga senza gesture residue;
- drag multiplo di post-it/testi;
- lasso su canvas affollata;
- fluidità percepita su 60 Hz e 120 Hz se i dispositivi lo consentono.

## Stress manuale consigliato

Usare una lavagna con:

- almeno 100 post-it;
- almeno 1.000 stroke;
- almeno 20.000 punti ink;
- background Puntini;
- zoom continuo e pan su area ampia;
- almeno 20 Undo/Redo consecutivi.

Annotare eventuali frame drop, input persi, salti di posizione o ritardi della gomma.

## Criterio di chiusura

0.54.3 può essere dichiarata FULL quando CI e Web sono verdi.
La dicitura CERTIFIED richiede il completamento della sezione real-device pertinente; in assenza di tablet/stylus fisico la parte stylus resta esplicitamente non certificata.
