# Notes 0.26A — Cloud Core

La 0.26 introduce la base cloud senza cambiare il principio local-first.

## 0.26A

- account email/password facoltativo;
- sessione persistente con refresh token cifrato tramite Android Keystore;
- sincronizzazione personale disattivata di default e attivabile esplicitamente;
- Room v9 con ownership cloud, revisioni remote, outbox, conflitti e cache predisposte per Shared Spaces;
- WorkManager one-shot + controllo periodico ogni 6 ore quando il cloud è attivo;
- tombstone tramite `deletedAt`, nessuna cancellazione remota distruttiva durante il normale uso;
- protezione cambio account: i record del vecchio account diventano `DETACHED` e non vengono adottati dal nuovo account;
- backup/import non conserva membership o ownership cloud: le copie importate nascono private/locali;
- GitHub Sync ignora i futuri record `SHARED`;
- nessuna service/secret key nell'APK. Il client usa solo URL progetto e publishable key.

Il backend di riferimento è `supabase/cloud_core.sql`. Le tabelle esposte hanno RLS e grant espliciti; l'RPC di compare-and-swap usa una funzione privilegiata nello schema `private` e un wrapper `security invoker` pubblico.

## Configurazione build

La build legge `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` dall'ambiente Gradle/CI. Se sono assenti, il modulo cloud rimane visibile come non configurato e l'app continua a funzionare offline senza regressioni.

## Fuori da 0.26A

Shared Spaces, inviti, ruoli e RLS di membership arrivano in 0.26B. Conflict Center e hardening multi-device arrivano in 0.26C.
