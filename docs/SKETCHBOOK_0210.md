# Notes — Sketchbook Pro & Universal Block Editor (v0.21.0)

## Novità principali in v0.21.0
1. **Documenti Sketchbook Multi-pagina**:
   - Supporto fino a 64 pagine per disegno vettoriale con navigazione rapida, aggiunta, duplicazione ed eliminazione sicura.
   - Paginazione gestita nel `SketchDocument` ed encoding JSON backward-compatible v1 e v2.
2. **Supporto Carta e Guide**:
   - Carta Bianca, a Righe, a Quadretti, a Puntini e modello Cornell.
   - Rendering hardware con linee e guide di riferimento.
3. **Forme Geometriche e Testo**:
   - Strumento Forme (linea, rettangolo, ellisse, freccia orientata) con spessori e palette colori dedicati.
   - Caselle di testo vettoriali integrate nella pagina, modificabili e cancellabili.
4. **Strumento Lasso & Modifica Tratti**:
   - Selezione rettangolare di tratti via Lasso, spostamento e cancellazione mirata.
5. **Supporto Pressione Stylus**:
   - Sensibilità alla pressione per tratti e tratti evidenziatore naturale (`InkPoint.pressure`).
6. **Integrazione Bidirezionale con il Block Editor**:
   - Blocco `DRAWING` nel `UniversalBlockEditor` con link portatile `[Sketch: Titolo](notes-sketch://sketchId)`.
   - Creazione rapida di nuovi sketch direttamente dal blocco o apertura immediata dello Sketchbook.
   - Retrocompatibilità garantita al 100% con file v1, backup snapshot v6 e sincronizzazione GitHub.
