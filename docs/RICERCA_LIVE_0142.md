# Notes 0.14.2 — Ricerca durante la digitazione

VersionCode18. Include la semplificazione Cerca 0.14.1, applicabile cumulativamente alla 0.14 corretta.

La query avvia immediatamente il filtro in background, senza Invio, debounce o attese artificiali. Il matching resta una sottostringa letterale case-insensitive nel titolo, corpo o tag. Casa → Casa di → Casa di Anna restringe i risultati; cancellare riporta quelli compatibili. Non è una ricerca semantica né per parole disordinate: Casa grande di Anna non contiene la frase intera Casa di Anna.

Durante il calcolo successivo si conserva l'ultimo elenco completato solo se note e tutti i filtri non testuali sono identici. La riga di stato indica Aggiornamento risultati e non presenta un vecchio conteggio come attuale. Il completamento pubblica i risultati della query corrente; i task cancellati non sostituiscono la ricerca più recente. Nessun vuoto artificiale fra battute; il messaggio Nessun risultato compare solo a ricerca conclusa. Cambi di archivio/cestino, dati o filtri invalidano la vecchia lista per non mostrare elementi fuori ambito. Azioni multiple disabilitate durante il calcolo.

Le righe di Cerca usano animazioni Compose di comparsa (160ms), scomparsa (120ms), riposizionamento (200ms) con chiavi stabili. In elenco ogni riga corrisponde a una nota; nella griglia a due colonne viene animata la riga, non uno spostamento indipendente di ogni singola card. Le durate non sono ritardi imposti alla ricerca né prestazioni misurate. Le animazioni rispettano la gestione di durata del framework Compose.
Riferimento API: https://developer.android.com/develop/ui/compose/lists#item-animations

Nessuna nuova dipendenza, nessuna migrazione o modifica dei formati backup/sync. Conservati il campo unico, il pannello filtri della 0.14.1, il tema e tutte le altre funzionalità.

Verifiche: sintassi Kotlin controllata. Nuovo caso JVM nel motore reale searchNotes per Casa/Casa di/Casa di Anna, case-insensitive, nessun risultato e cancellazione del testo. Nei sorgenti sono presenti 206 test JVM (205 precedenti +1). 198 test Kotlin/JUnit locali eseguiti e superati, inclusa la nuova regressione; 8 casi Robolectric esclusi dal runner locale; l'esecuzione locale non sostituisce Gradle Android né i suoi report XML.
Collaudo Android aperto: digitare rapidamente e cancellare, risultato vuoto, filtri mentre si digita, griglia/elenco, digitazione con sync/dati in aggiornamento, tastiera/font grandi, animazioni di sistema disattivate. Non sono state visualizzate schermate o misurate prestazioni su dispositivo in locale.
