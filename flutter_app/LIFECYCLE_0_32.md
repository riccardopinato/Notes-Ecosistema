# Data Lifecycle Audit — Notes Ecosistema 0.32.0

## Obiettivo

La 0.32 rende esplicito il ciclo di vita dei contenuti senza cambiare lo schema Room v8.

Policy standard:

`contenuto attivo -> archivio opzionale -> cestino/soft delete -> ripristino -> eliminazione definitiva`

L'eliminazione definitiva è consentita solo per elementi già nel cestino.

## Invarianti

1. Il cestino è reversibile.
2. Il purge è irreversibile e richiede conferma UI.
3. Un task cestinato deve restare raggiungibile dal cestino universale.
4. Un elemento cestinato non può generare reminder.
5. Il purge rimuove dati interni non più utili nello stesso confine transazionale.
6. Gli allegati content-addressed vengono eliminati solo se non più referenziati da nessuna nota o bozza.
7. Rimuovere un contenuto da uno Shared Space non equivale a cancellarlo localmente.
8. Prima del purge locale di un elemento condiviso, Notes prova a rimuoverlo dagli spazi modificabili.
9. Se esiste uno spazio collegato che l'identità corrente non può modificare, il purge viene bloccato.
10. Nessuna cancellazione deve richiedere una migrazione distruttiva del database.

## Matrice entità

| Entità | Soft delete / archivio | Ripristino | Purge / cascata | Stato 0.32 |
|---|---|---|---|---|
| Note Markdown | cestino + archivio | sì | draft, revisioni, content blocks; allegati orfani | hardening completato |
| Checklist | parte della nota | con la nota | con la nota | coperto |
| Task | cestino | sì, anche dal cestino universale | note row + draft/revisioni/blocchi eventuali; reminder escluso | hardening completato |
| Reminder | derivato dal task | ritorna se task ripristinato e ancora valido | scheduler riceve payload senza task eliminati | coperto/testato |
| Sketch | cestino come Note visuale | sì | row + metadati DB; asset solo se orfani | coperto dal modello Note |
| Whiteboard / Mind Map | cestino come Note visuale | sì | row + metadati DB; asset solo se orfani | coperto dal modello Note |
| Allegati | reference-based | con il contenuto | cleanup solo se key SHA-256 non referenziata | coperto |
| Draft editor | temporaneo | n/a | eliminato quando la nota entra nel cestino o viene purgata | hardening completato |
| Revision history | mantiene storia durante soft delete | disponibile dopo restore | eliminata al purge | hardening completato |
| Content blocks | restano durante soft delete | disponibili dopo restore | eliminati al purge | hardening completato |
| Raccolte | eliminazione solo se completamente vuote | n/a | DB impedisce eliminazione se note/draft/revisioni le referenziano | già presente |
| Shared Space membership | tombstone/clock separati | merge-based | unlink prima del purge locale; blocco senza permesso | hardening completato |
| Shared Space | metadati separati dal DB note | secondo contratto Shared Spaces | non viene eliminato dal purge di una nota | invariato |
| Template personali | rappresentati come note archiviate | tramite lifecycle Note | stesso lifecycle Note | coperto |
| Saved searches | preferenze locali separate | n/a | gestione dedicata | fuori dal purge Note |

## Correzioni 0.32

### Draft nel cestino

Prima della 0.32, `trash(id)` impostava `deletedAt` ma poteva lasciare una bozza con lo stesso ID. Questo poteva rendere incoerente il backup, perché il codec rifiuta correttamente una bozza associata a una nota eliminata.

Ora il passaggio nel cestino elimina la bozza nello stesso transaction boundary.

### Task non recuperabili

La ricerca Note escludeva sempre gli elementi `isTask`, incluso il filtro Cestino. Un task cestinato quindi spariva dall'interfaccia.

Ora il filtro Cestino include anche i task eliminati; la card non apre l'editor sbagliato e mostra solo:

- Ripristina;
- Elimina definitivamente.

### Eliminazione definitiva

`deleteForever(id)` richiede `deletedAt != null` e rimuove in transazione:

- draft;
- revision history;
- content blocks;
- record note/task/visuale.

Dopo il purge, il controller rimuove l'elemento dallo stato senza full reload quando possibile.

### Shared Spaces

Se l'ID è ancora presente in uno o più Shared Spaces:

- Notes verifica l'identità corrente;
- verifica `role.canEdit`;
- esegue `unlinkContent` per ogni spazio modificabile;
- solo dopo esegue il purge locale;
- pianifica Live Sync;
- se almeno uno spazio non è modificabile, il purge è bloccato.

Questo evita riferimenti condivisi orfani o cancellazioni locali che simulano una cancellazione “per tutti”.

### Allegati

Il purge non elimina direttamente un file dal content store perché una stessa key SHA-256 può essere referenziata da più contenuti.

Dopo il purge viene eseguito il cleanup sicuro:

- si ricostruisce il set di key ancora referenziate da note e draft;
- vengono eliminati solo i file non più referenziati.

## Test automatici aggiunti

`test/lifecycle_test.dart` verifica almeno:

- task eliminati raggiungibili nel cestino;
- task attivi esclusi dalla vista note normale;
- restore senza perdita di task metadata;
- conservazione dello stato archivio precedente;
- reminder payload che esclude task eliminati, archiviati, completati o privi di reminder.

## Limiti e acceptance reale

Restano da validare su device fisico per una certificazione stabile:

- cancellazione reale delle notifiche reminder dopo trash/purge;
- notifica Shared Spaces in background/app chiusa;
- comportamento Doze/OEM;
- installazione/upgrade dell'APK release firmato.

Questi gap devono essere riportati nell'Evidence Bundle: non vengono considerati implicitamente superati.
