# Completamento 0.10.1 — code 12

## Audit dello ZIP (4)
La compilazione e i 90 test sono stati dichiarati dall’utente. L’export contiene 13 classi di test JVM. La parte dati di 0.10 è presente, ma l’interfaccia NotesApp non richiama SearchControls o BulkActions; EditorViewModel non gestisce i tag; mancano TagsEditor e SearchControls; NotesViewModel non espone bulkEdit/bulkBusy. BulkActions esiste ma non è collegato alla schermata.
Mancano TagsTest, BulkEditTest, AdvancedSearchTest, TagsBackupTest e le estensioni dei test sync: 34 test JVM in totale. Mancano anche TagsAndBulkRepositoryTest e TagsMigrationTest, e tre test strumentali non registrano la migrazione 4→5.
Il successo della compilazione non dimostra quindi che tutte le funzioni richieste siano raggiungibili dall’utente.

## Correzione
Ripristinati i file completi dell’interfaccia e dei test, preservando il codice dati già corretto dell’export. Ora i tag vengono caricati, modificati, persistiti come bozze, salvati, duplicati e recuperati dalle revisioni. Cerca richiama la ricerca combinata; la selezione richiama le azioni multiple transazionali del repository. Avviso compatibilità GitHub aggiornato a 0.10.
Room rimane 5: nessuna nuova migrazione. Conservato byte per byte lo schema 5 KSP dell’export. Nessuna modifica a firma, applicationId, dipendenze, credenziali o dati utente.

## Verifiche
116 test Kotlin locali sul codice corretto: vedere il risultato del runner. Non è l’intera suite Android Gradle. Aggiunti/ripristinati 34 test JVM rispetto all’export: il conteggio atteso della suite Gradle è 124, ma va verificato dai report XML reali e NON dichiarato eseguito in anticipo.
Compilazione Android, test strumentali e GitHub su due dispositivi non eseguiti qui. I 9 test strumentali ripristinati sono da eseguire con ADB; restano aperte anche le prove precedenti di migrazione e sync.

## Accettazione prima di archiviare
1. Build APK e suite Gradle completa, conteggio dai report XML.
2. Nell’editor deve apparire Aggiungi tag; un tag salvato deve comparire sulla scheda e sopravvivere a riapertura, bozza, duplicazione e revisione.
3. In Note deve apparire Seleziona note; scegliere due note e applicare un tag, archiviare e ripristinare. Una bozza attiva deve bloccare l’intero gruppo.
4. In Cerca devono apparire raccolta, preferiti, fissate, attività, tag e opzione Tutti/Almeno uno; verificare che cambino davvero i risultati.
5. Conservare schema Room 5 e verificare backup/import v3 e sync tra client compatibili.
Solo dopo questi controlli l’integrazione 0.10 è completata; la v0.11 sarà un aggiornamento separato.
