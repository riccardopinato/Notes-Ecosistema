# Notes — Ecosistema 0.18.0 · Modelli personali

## Integrazione
- Crea → Modelli apre una galleria con ricerca per titolo, quattro modelli predefiniti, modelli personali, anteprima testuale (primi 2.000 caratteri), utilizzo e modifica.
- Nell’editor Crea modello salva il contenuto corrente, inclusi tag e riferimenti agli allegati, in una NUOVA nota archiviata con tag `modello`. Originale e relativa bozza non vengono modificati. La nuova copia ha UUID autonomo, Inbox come raccolta, nessun preferito/pin o dato attività. Il salvataggio avviene con Mutex e transazione Room, inserimento che fallisce in caso di collisione; nessuna sovrascrittura.
- I modelli creati sono archiviati per non alimentare le checklist attive. Modifica modello apre l’editor normale: modifica titolo/contenuto, salva; rimuovi il tag per escludere il modello dalla galleria. La nota resta in Archivio. Si può anche cestinare tramite le azioni esistenti.
- È possibile contrassegnare una nota normale aggiungendo `modello`: in quel caso rimane nel suo stato originale; archiviala se non vuoi le sue checklist tra le attività.
- Usa modello apre una nuova bozza, da salvare o scartare. Copia titolo, corpo e tag, escluso `modello`; nuova nota in Inbox, attiva, senza pin/preferiti/cronologia o metadati della sorgente.
- Opzione Riparti con tutte le spunte da completare: azzera le checklist riconosciute, preserva codice fenced, CRLF, testo e sottovoci. Disattivabile.
- Variabili letterali `{{data}}` (dd/MM/yyyy), `{{ora}}` (HH:mm), `{{giorno}}` (nome italiano) vengono espanse nel titolo/corpo al primo utilizzo, anche dentro codice. Variabili sconosciute restano inalterate. Non sono formule o script. Istante e fuso persistiti nel SavedStateHandle; una bozza già esistente prevale e non rilegge la sorgente.
- Galleria usa la versione SALVATA; non incorpora bozze del modello. Include modelli archiviati, esclude cestino, attività autonome e disegni. Lo sketchbook non è convertito in modello testuale.

## Compatibilità e limiti
Room 7 e tutti gli schemi invariati; backup JSON e SyncCodec v6, bundle multimediale v1 invariati. Nessuna nuova dipendenza o permesso. Versione 0.18.0/code22; applicationId/firma/toolchain preservati. Note modello e tag sono già inclusi nei backup e nella sincronizzazione ordinaria; allegati condividono le chiavi SHA-256. Il backup JSON semplice non include i binari: usare il completo ZIP. Collegamenti interni mantengono le destinazioni originali; importCopies conserva il proprio rimappamento preesistente.
Non serve un formato template separato. Restano i limiti globali di note/backup/sync. Massimo 20 tag inclusivo di `modello`: se la nota ha già 20 altri tag si mostra un errore senza eliminarne alcuno. Nessun corpo oltre 200.000 caratteri o titolo oltre 8.000 dopo l’espansione. Non vengono copiate raccolta, scadenze o ricorrenze.
La galleria filtra in background con Dispatchers.Default. Nessuna prestazione misurata o benchmark dichiarato.

## Verifiche locali reali
- 323 test Kotlin/JUnit eseguiti con successo tramite runner JVM locale, inclusi 24 nuovi PersonalTemplatesTest: variabili/fuso, reset e codice, sorgenti archiviate/cestinate, tag/limiti, allegati/collegamenti, backup e codec GitHub.
- Sorgenti JVM: 331 @Test (307 preesistenti +24). Gli 8 test Robolectric preesistenti non fanno parte del runner locale.
- Quattro nuovi TemplateRepositoryTest strumentali predisposti: copia archiviata, indipendenza originale/bozza, UUID distinti, importazione. NON ESEGUITI.
- Non disponibili SDK Android, Gradle Android o ADB nell’ambiente locale: APK e :app:testDebugUnitTest NON ESEGUITI qui. UI Compose non compilata/visualizzata su Android. Nessuna nuova misura grafica o di fluidità.

## Collaudo richiesto in AI Studio / Android
1. Applicare tutti i file completi, compilare APK e :app:testDebugUnitTest; contare realmente i report XML (331 attesi), conservare test preesistenti.
2. Crea → Modelli: ricerca, anteprima, modello predefinito/personale; tema chiaro/scuro, tastiera, display piccolo, caratteri 1.3x/2x.
3. Creare modello da nota con bozza, tag, checklist, allegati e collegamento. Verificare originale invariato, copia in Archivio, assenza delle sue checklist nel planner.
4. Usare modello con reset attivo/disattivo e variabili. Salvare/scartare. Ruotare e ricreare il processo dopo memorizzazione della bozza; eliminare il modello originale e verificare che la nuova bozza si recuperi comunque.
5. Modificare/rititolare il modello; rimuovere tag, cestinare/ripristinare. Tentare 20 tag pieni e contenuto oltre limite; nessuna scrittura parziale.
6. Export/import JSON e ZIP completo; GitHub reale fra due installazioni con allegati. Non dichiarare tali prove se non eseguite.
7. Eseguire androidTest se ADB disponibile. Restano aperti anche test fisici multimedia, Focus, migrazioni e sync delle fasi precedenti.
