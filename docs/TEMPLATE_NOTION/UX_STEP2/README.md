# UX STEP 2 — Notes | Libreria di lettura

**STATO:** DRAFT UX / ATTESA APPROVAZIONE. **Fonte:** TPLUX-REF-0004, E2 export strutturale. Nessun contenuto del Book Tracker commerciale è stato copiato e nessuna licenza alla rivendita è implicita.

**Baseline:** Notes `70e8e963baaa6d1e79390c7862db087baaf3b9b8`, Core `d4ed1185d36d419228fba6b57a979cde308bd321`. [Prototipo HTML interattivo](PROTOTIPO_BOOK_TRACKER.html) con dati esclusivamente inventati, non collegato a Flutter.

## Scelta di prodotto per il pilota

**Biblioteca personale** gratuita sotto **Modelli** già esistente (non uno store). L'utente crea **una nota editoriale modificabile** suddivisa in Da leggere / In lettura / Conclusi, appunti e riflessioni. Non promette un database Books, statistiche o cover reali. La fase ricca (più note per libri, raccolte, metadati e progressi calcolati) richiederebbe ammissione prodotto e verifica dei writer canonici.

## Confronto con codice reale

- `flutter_app/lib/src/domain/templates.dart`: `PersonalTemplates.instantiate`, `PageTemplates`; oggi genera `TemplateContent`, non un database libri.
- `flutter_app/lib/src/screens/templates_screen.dart`: schermata `Modelli`, ricerca, card, anteprima e callback `onUse`; punto d'ingresso naturale.
- `flutter_app/lib/src/domain/note.dart`: `Note`, `NoteCollection`, `collectionId`.
- `flutter_app/lib/src/domain/properties.dart`: proprietà universali (non inferire che schemi Book/Pages siano pronti).
- `flutter_app/lib/src/theme/notes_theme.dart`: M3, blu `#3559E0`, background `#F6F4EF`, surface `#FFFDFA`.

## Flusso UX progettato

1. **Modelli / Galleria:** card Libreria personale con `Gratuito` e `Anteprima`.
2. **Anteprima:** contenuto della futura nota renderizzato nell'identità Notes, esempio sintetico etichettato.
3. **Personalizza:** titolo e scelta se includere checklist Da leggere; preview aggiornata.
4. **Conferma:** riepilogo esatto di una nota, destinazione privata, `Crea nota`.
5. **Maxi-step 3:** attraverso il writer Notes, materializza una nota e la apre nell'editor; attivazione del backend **non effettuata oggi**. Retry senza duplicati, error rollback e account isolation da testare.
6. **Rimozione futura del modello:** scollega la voce dal catalogo, senza cancellare note create dall'utente.

## Copia originale illustrativa

```text
# La mia biblioteca
## Da leggere
- [ ] Aggiungi il prossimo titolo
## In lettura
Titolo: ___
Autore: ___
Appunti miei: ___
## Conclusi
Titolo: ___
Cosa mi è rimasto: ___
```

## Gate da approvare

La UX proposta è una **singola nota**. Approvazione separata obbligatoria per eventuale libreria multi-entity, rating, pagine lette/totali, statistiche e vendita premium. UI 360dp/tablet, Light/Dark, caratteri grandi, tastiera, 48dp, IT/EN/ES/FR/DE/PT, screen reader, test creazione/reset/idempotenza/backup in Step 3. Nessuna immagine/libro/copertina/proprietà di terzi in produzione. Il demo **non** è una prova di test su dispositivo.

**Decisione attesa:** approvare/modificare/rifiutare la struttura e l'esperienza prima di dare `product_approved` o iniziare i writer Flutter.
