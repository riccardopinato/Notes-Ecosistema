# Notes — Ecosistema 0.10.0

VersionCode 11. Baseline: export utente 0.9.0, applicationId it.notes.ecosystem.lymlyc. Nessuna nuova dipendenza.

## Funzioni integrate
- Tag multipli nell’editor, nelle schede, nelle bozze e nella cronologia; duplicazione, importazione, export e GitHub conservano i tag.
- Tag normalizzati NFC/minuscolo, massimo 20 per nota e 40 caratteri ciascuno. Lettere Unicode, numeri, trattino e underscore; # iniziale facoltativo. Nessuna rinomina globale dei tag.
- Selezione fino a 500 note e 11 azioni: archivia/rimuovi archivio, fissa/rimuovi fissata, preferita/rimuovi preferita, sposta raccolta o Inbox, aggiungi/rimuovi tag, cestina/ripristina. Dialog con conteggio e riepilogo prima dell’applicazione.
- Operazioni locali in una transazione: tutti gli elementi vengono validati prima delle scritture. Se una nota è cambiata, ha una bozza, è aperta o la raccolta è scomparsa, nessuna nota del gruppo viene aggiornata. Rinnovare la selezione dopo un conflitto. Nessuna eliminazione definitiva.
- Cerca combina testo letterale (titolo/corpo/tag), raccolta, preferiti, fissate, presenza di attività e tag con Tutti/Almeno uno. Archivio/cestino restano ambiti espliciti. Le attività si riferiscono al corpo salvato. Nessuna sintassi di query o ricerca nelle revisioni.
- Filtraggio e suggerimenti tag calcolati in background; risultati legati agli input, senza mostrare vecchi risultati sotto nuovi filtri.

## Persistenza e compatibilità
Room 5, migrazione additiva 4→5: tagsJson TEXT NOT NULL DEFAULT '[]' in notes, drafts, note_revisions. Gli schemi 1–4 restano invariati. Generare 5.json con KSP durante la compilazione Android: non inventare identityHash. Nessuna migrazione distruttiva.
Backup JSON v3 e documenti GitHub v3; lettura v1/v2/v3. I vecchi dati ricevono tag vuoti. Aggiornare TUTTE le installazioni a 0.10 prima della sincronizzazione sullo stesso repository: le versioni precedenti non leggono v3.
Bozze incluse nel backup JSON, escluse da GitHub. Cronologia locale esclusa da backup e GitHub, come prima. Il formato esterno dei checkpoint sync resta invariato; i documenti interni diventano v3 quando riscritti.
La transazione delle azioni multiple è locale. GitHub mantiene sincronizzazione/checkpoint per singolo file: non garantisce visibilità atomica dell’intero gruppo su altri dispositivi. Restano limiti 500 note, 256 KiB per documento, 5 MiB complessivi sync; backup import massimo 5 MiB.

## Verifiche effettive di questo pacchetto
- 116 test JVM reali superati, compilando i sorgenti Kotlin dominio/codec/motore sync con runtime locale. Inclusi 34 test nuovi su tag, ricerca, azioni multiple, backup e sincronizzazione.
- Le tre istruzioni SQL della migrazione eseguite sul vero schema 4 in SQLite: note, bozze, revisioni e flag conservati; tag vuoti; controllo foreign key superato. Questo non sostituisce la validazione Room su Android.
- Aggiunti 9 test strumentali: 8 repository (tag, cronologia, import, batch, conflitti, bozze/editor, limiti) e 1 migrazione 4→5. NON eseguiti qui.
- NON eseguiti qui: compilazione Android/APK, intera suite Gradle (inclusi gli 8 test storici basati su Robolectric), test strumentali e GitHub reale tra due installazioni. I 116 non sono il conteggio della suite Gradle completa.

## Collaudo da chiudere in AI Studio/dispositivo
1. Compilare APK ed eseguire :app:testDebugUnitTest; riportare conteggi dai report XML, non dedurli da questo documento.
2. Generare schema Room 5 con KSP. Se ADB disponibile, eseguire :app:connectedDebugAndroidTest, incluse tutte le migrazioni precedenti.
3. Aggiornare una installazione 0.9 con note fissate/archiviate, bozze e revisioni: nessuna perdita; tag inizialmente vuoti.
4. Aggiungere/rimuovere tag, salvare/scartare bozza, ricreare editor e ripristinare revisione; verificare i tag della versione scelta.
5. Selezionare note, spostare/archiviare/applicare tag/cestinare/ripristinare. Simulare una bozza o modifica concorrente: nessuna scrittura parziale locale.
6. Combinare testo, raccolta, tag AND/OR, preferiti, fissate, attività; provare archivio/cestino, temi e caratteri grandi.
7. Export/import v3 e vecchi backup v1/v2. GitHub privato di prova con due installazioni 0.10: tag, conflitti e preservazione delle bozze.

Focus, pianificazione, allegati/disegno e attività con ID stabili restano fasi successive, non implementate da questo aggiornamento.
