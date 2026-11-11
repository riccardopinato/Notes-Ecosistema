#!/usr/bin/env python3
"""Real Chromium localStorage smoke through an isolated QA-only Flutter entrypoint.

Uses the production WebWorkspaceStore and the browser SharedPreferences plugin.
Does NOT test the production editor UI, authenticated sessions or real devices.
"""
import hashlib
import json
import os
from pathlib import Path
from playwright.sync_api import sync_playwright

URL = os.environ.get("QA_URL", "http://127.0.0.1:8877/")
OUTPUT = Path(os.environ.get("QA_OUTPUT", "qa-results/browser-workspace.json"))
CASES = []


def record(name, assertion):
    assertion()
    CASES.append({"id": name, "status": "PASS", "mode": "CHROMIUM_REAL_LOCALSTORAGE"})


def invoke(page, action, **data):
    response = page.evaluate(
        """async (request) => {
          if (typeof window.notesWorkspaceQa !== 'function') {
            throw Error('QA bridge not initialized');
          }
          return JSON.parse(await window.notesWorkspaceQa(JSON.stringify(request)));
        }""",
        {"action": action, **data},
    )
    return response


def expect_ok(result):
    assert result["ok"] is True, result
    return result


def expect_error(result, contains):
    assert result["ok"] is False, result
    assert contains.lower() in result["error"].lower(), result
    return result


def open_app(page):
    diagnostics = []
    page.on("pageerror", lambda error: diagnostics.append(f"JS_ERROR {error}"))
    page.on(
        "console",
        lambda message: diagnostics.append(f"CONSOLE {message.type}: {message.text}")
        if message.type in ("error", "warning") else None,
    )
    page.on(
        "requestfailed",
        lambda request: diagnostics.append(f"REQUEST_FAILED {request.url}"),
    )
    response = page.goto(URL, wait_until="domcontentloaded", timeout=30000)
    try:
        page.wait_for_function(
            "typeof window.notesWorkspaceQa === 'function'", timeout=30000
        )
    except Exception as error:
        body = page.locator("body").inner_text(timeout=5000)[:500]
        state = page.evaluate(
            """() => ({
              readyState: document.readyState,
              scripts: Array.from(document.scripts).map(s => s.src || 'inline'),
              bodyText: document.body?.innerText?.slice(0,300) || '',
              flutterElements: document.querySelectorAll('flutter-view').length,
              bridge: typeof window.notesWorkspaceQa
            })"""
        )
        raise RuntimeError(
            f"QA bridge not available: status={response.status if response else None}; "
            f"state={state}; body={body!r}; browser={diagnostics[-20:]}"
        ) from error


def slots(page):
    return page.evaluate(
        """() => Object.fromEntries(
          Object.keys(localStorage)
            .filter(k => k.includes('notes.web.workspace.v1.'))
            .map(k => [k, localStorage.getItem(k)])
        )"""
    )


def mutate_slot(page, suffix, raw):
    return page.evaluate(
        """({suffix, raw}) => {
          const key = Object.keys(localStorage)
            .find(k => k.endsWith('notes.web.workspace.v1.' + suffix));
          if (!key) throw Error('Journal slot not found: ' + suffix);
          localStorage.setItem(key, raw);
          return key;
        }""",
        {"suffix": suffix, "raw": raw},
    )


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    outcome = "FAIL"
    failure = None
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            a = browser.new_context(locale="en-US")
            page = a.new_page()
            open_app(page)
            record("NBR-01-empty", lambda: (
                expect_ok(invoke(page, "load"))["count"] == 0
                or (_ for _ in ()).throw(AssertionError("not empty"))
            ))
            record("NBR-02-save", lambda: (
                expect_ok(invoke(page, "save", title="Synthetic Alpha"))["title"]
                == "Synthetic Alpha"
                or (_ for _ in ()).throw(AssertionError("write failed"))
            ))
            page.reload(wait_until="domcontentloaded")
            page.wait_for_function("typeof window.notesWorkspaceQa === 'function'")
            record("NBR-03-reopen", lambda: (
                expect_ok(invoke(page, "load"))["title"] == "Synthetic Alpha"
                or (_ for _ in ()).throw(AssertionError("not persisted"))
            ))
            expect_ok(invoke(page, "save", title="Synthetic Beta"))
            exported = expect_ok(invoke(page, "export"))["backup"]

            def check_export():
                obj = json.loads(exported)
                assert obj["format"] == "notes-web-workspace"
                assert obj["schema"] == 1
                assert obj["sha256"] == hashlib.sha256(
                    obj["payload"].encode("utf-8")
                ).hexdigest()
                assert "Synthetic Beta" in obj["payload"]
            record("NBR-04-export-hash", check_export)

            b = browser.new_context(locale="en-US")
            page_b = b.new_page()
            open_app(page_b)
            record("NBR-05-clean-import", lambda: (
                expect_ok(invoke(page_b, "import", backup=exported))["count"] == 1
                or (_ for _ in ()).throw(AssertionError("import failed"))
            ))
            page_b.reload(wait_until="domcontentloaded")
            page_b.wait_for_function("typeof window.notesWorkspaceQa === 'function'")
            record("NBR-06-import-reopen", lambda: (
                expect_ok(invoke(page_b, "load"))["title"] == "Synthetic Beta"
                or (_ for _ in ()).throw(AssertionError("import lost on reload"))
            ))
            tampered = exported.replace("Synthetic Beta", "Synthetic Fraud")

            def check_tampered():
                before = slots(page_b)
                expect_error(invoke(page_b, "import", backup=tampered), "checksum")
                assert slots(page_b) == before, "Invalid import mutated storage"
            record("NBR-07-tampered-backup", check_tampered)

            def check_fallback():
                mutate_slot(page, "b", "definitely-corrupt")
                page.reload(wait_until="domcontentloaded")
                page.wait_for_function("typeof window.notesWorkspaceQa === 'function'")
                recovered = expect_ok(invoke(page, "load"))
                assert recovered["title"] == "Synthetic Alpha", recovered
                assert recovered["recoveredPrevious"] is True, recovered
            record("NBR-08-corrupt-newest-fallback", check_fallback)

            def check_both_corrupt():
                mutate_slot(page, "a", "also-corrupt")
                before = slots(page)
                page.reload(wait_until="domcontentloaded")
                page.wait_for_function("typeof window.notesWorkspaceQa === 'function'")
                expect_error(invoke(page, "load"), "non leggibile")
                expect_error(
                    invoke(page, "save", title="Forbidden after corruption"),
                    "non leggibile",
                )
                assert slots(page) == before, "Corrupt data overwritten"
            record("NBR-09-both-slots-fail-closed", check_both_corrupt)

            def check_recovery():
                expect_ok(invoke(page, "recover", backup=exported))
                assert len(slots(page)) == 1, slots(page)
                page.reload(wait_until="domcontentloaded")
                page.wait_for_function("typeof window.notesWorkspaceQa === 'function'")
                assert expect_ok(invoke(page, "load"))["title"] == "Synthetic Beta"
            record("NBR-10-confirmed-recovery", check_recovery)

            def check_stale_tab():
                stale = a.new_page()
                open_app(stale)
                assert expect_ok(invoke(stale, "load"))["title"] == "Synthetic Beta"
                expect_ok(invoke(page, "save", title="Synthetic Gamma"))
                expect_error(invoke(stale, "save", title="Should not clobber"), "altra scheda")
                assert expect_ok(invoke(page, "load"))["title"] == "Synthetic Gamma"
                stale.close()
            record("NBR-11-stale-tab-rejected", check_stale_tab)

            def check_quota():
                before = slots(page)
                expect_error(invoke(page, "quota"), "troppo grande")
                assert slots(page) == before, "Quota guard altered acknowledged data"
                assert expect_ok(invoke(page, "load"))["title"] == "Synthetic Gamma"
            record("NBR-12-quota-fail-closed", check_quota)

            a.close()
            b.close()
            browser.close()
            outcome = "PASS"
    except Exception as exc:
        failure = f"{type(exc).__name__}: {exc}"
        print("FAIL:", failure)
        raise
    finally:
        OUTPUT.write_text(
            json.dumps(
                {
                    "qa": "Notes Web Workspace Chromium localStorage integration",
                    "result": outcome,
                    "cases": CASES,
                    "failure": failure,
                    "limits": [
                        "QA-only Flutter Web entrypoint, not production editor UI",
                        "Chromium headless browser; no installed Android/iOS PWA",
                        "No user data, remote account, Google Play or cloud",
                        "Not an atomicity proof for simultaneous tab writes",
                    ],
                },
                indent=2,
                ensure_ascii=False,
            ) + "\n",
            encoding="utf-8",
        )
        print("Result:", OUTPUT, outcome, "cases:", len(CASES))


if __name__ == "__main__":
    main()
