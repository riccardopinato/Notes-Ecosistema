from pathlib import Path
from urllib.request import Request, urlopen
from concurrent.futures import ThreadPoolExecutor
import json

root = Path(__file__).resolve().parents[1]
repos = [
("TheCodeMonks/Notzz-App", "Base Android e organizzazione note", "Architettura e persistenza", "1"),
("laurent22/joplin", "Note multipiattaforma e sincronizzazione", "Offline, import/export e sync", "2, 7"),
("karakeep-app/karakeep", "Raccolta di link, note e immagini", "Capture Hub e archivio web", "4, 5"),
("notable/notable", "Appunti Markdown", "Esperienza editor e organizzazione", "3"),
("BoostIO/BoostNote-Legacy", "Repository legacy di note per sviluppatori", "Snippet e note tecniche", "3, 6"),
("codexu/note-gen", "Cattura e organizzazione di note con AI", "Inbox multimodale e assistenza opzionale", "4, 8"),
("0x7c13/Notepads", "Editor di testo Windows", "Semplicità editor e gestione documenti", "2, 3"),
("glushchenko/fsnotes", "Appunti Markdown per Mac e iPhone", "Flussi desktop/mobile", "3, 7"),
("taniarascia/takenote", "App web per appunti", "Navigazione e interazione editor", "1, 3"),
("massCodeIO/massCode", "Workspace locale per sviluppatori", "Snippet e strumenti nel workspace", "6"),
("standardnotes/app", "Note e file con cifratura end-to-end", "Modello di privacy e sync", "7"),
("toeverything/AFFiNE", "Workspace per documenti e pianificazione", "Convergenza documenti e canvas", "6"),
("usememos/memos", "Note leggere e cattura rapida", "Velocità della cattura", "4"),
("silverbulletmd/silverbullet", "Produttività basata su Markdown e scripting", "Estensibilità e automazioni", "8"),
]
def fetch(item):
    repo, description, inspiration, phase = item
    result = dict(repository=repo, url="https://github.com/"+repo, description=description,
                  inspiration=inspiration, phase=phase, checked="2026-09-10", code_reused=False)
    try:
        request = Request("https://api.github.com/repos/"+repo, headers={"User-Agent": "Notes-Source-Vault"})
        with urlopen(request, timeout=25) as response:
            data = json.load(response)
        result.update(default_branch=data["default_branch"], archived=data["archived"],
                      license_reported_by_github=(data.get("license") or {}).get("spdx_id", "non rilevata"),
                      canonical_url=data["html_url"], description_upstream=data.get("description"))
    except Exception as error:
        result.update(metadata_error=str(error), license_reported_by_github="da verificare")
    return result
with ThreadPoolExecutor(max_workers=5) as pool:
    results = list(pool.map(fetch, repos))
(root/"docs/source-vault.json").write_text(json.dumps(results, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
lines = [
"# Source Vault — v0.1", "",
"Archivio delle 14 fonti recuperate dalla [conversazione originale](https://chatgpt.com/share/6aa2968d-16f0-83ed-bdb1-482746bc0364). Consultazione: 10 settembre 2026.",
"",
"Le prime 11 provengono dall’elenco iniziale; AFFiNE, Memos e SilverBullet erano le aggiunte della conversazione. Le descrizioni sono sintetiche; la colonna Spunto indica una nostra direzione di studio, non un’analisi del codice completata.",
"",
"| Fonte | Descrizione | Spunto per l’app | Fase | Licenza segnalata da GitHub |",
"|---|---|---|---|---|",
]
for r in results:
    lines.append(f"| [{r['repository']}]({r['url']}) | {r['description']} | {r['inspiration']} | {r['phase']} | {r['license_reported_by_github']} |")
lines += [
"", "## Stato dell’analisi", "",
"README/pagine principali consultati. Metadati pubblici recuperati tramite GitHub API e salvati in [JSON](source-vault.json). Nessun clone, audit tecnico approfondito o riuso di codice eseguito.",
"",
"La licenza indicata è il metadato restituito da GitHub, non una verifica per ogni file, versione o sottoprogetto. NOASSERTION/non rilevata richiede lettura dei file pertinenti. Per ogni futuro riuso registrare commit, file, licenza e attribuzioni. Non riprendiamo automaticamente le etichette della chat precedente.",
"",
"## Come aggiungere fonti", "",
"Aggiungere un record a questo archivio e al JSON: URL, motivo di interesse, fase, stato analisi, eventuale commit e file riusati. Conservare sempre il link originale; distinguere fonti consultate e implementazioni integrate.",
"",
"## Prossime letture mirate", "",
"1. Notzz: struttura dei livelli e flussi di stato, confrontandoli con la Foundation originale.",
"2. Joplin: import/export e gestione offline per la fase 2/7.",
"3. Karakeep e Memos: percorso di cattura e organizzazione differita.",
"4. AFFiNE e SilverBullet: modello dei contenuti ed estensioni nella fase workspace.",
]
(root/"docs/SOURCE_VAULT.md").write_text("\n".join(lines)+"\n", encoding="utf-8")
with urlopen("https://raw.githubusercontent.com/gradle/gradle/v8.11.1/LICENSE", timeout=30) as response:
    (root/"gradle/LICENSE").write_bytes(response.read())
print(json.dumps([{"repo": r["repository"], "license": r["license_reported_by_github"], "error": r.get("metadata_error")} for r in results], indent=2))
