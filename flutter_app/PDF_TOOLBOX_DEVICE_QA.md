# PDF Toolbox — Android QA / release acceptance

State: **NOT RUN**. This is a reproducible protocol, not a test receipt.

## Two separate release gates

1. **Merge/code gate**: exact-head Flutter tests, analyzer, Android debug/release APK and Play AAB builds, APK size regression guard, reviewed code, license inventory. The PDF Toolbox must be disabled in ordinary app builds until gate 2 passes.
2. **Feature exposure / Play release gate**: real device PDF operations with documented fixtures, original-file SHA comparison, visual and resource checks, memory and failure handling, third-party notices and vulnerability review. This gate cannot be certified from CI compilation.

Normal builds hide the toolbox. Only QA APKs compiled with `--dart-define=NOTES_ENABLE_PDF_TOOLBOX=true` expose it. This does **not** enable PDF sanitization or password protection.

## QA procedure (physical Android 10+ handset)

Record device make/model, Android version, app versionCode, APK SHA-256, operator, timestamp and source fixture SHA-256. Use synthetic documents only, never personal records. In PDF Workspace open each original, choose **PDF Toolbox · crea una copia**, perform the operation and save the output via the Android document picker. Re-open every exported copy in an independent PDF reader. Record page count, order, visible text/image fidelity, dimensions and annotations, and compare original SHA-256 before/after.

| ID | Scenario | Pass criteria | Result |
| --- | --- | --- | --- |
| QA-PDF-01 | 3-page textual PDF; extract pages 2–3 | 2 pages, correct labels and fonts; source unchanged | NOT RUN |
| QA-PDF-02 | Two PDFs: text, embedded fonts and bitmap images | Merged page count/order correct, text/images preserved; both sources unchanged | NOT RUN |
| QA-PDF-03 | PDF with inherited `/Pages /Resources`; reorder [3,1,2] | Expected ordering and no missing fonts/images | NOT RUN |
| QA-PDF-04 | Rotate PDF 90/180/270 degrees | Page orientations correct, no clipping/content loss | NOT RUN |
| QA-PDF-05 | Encrypted/password-protected PDF | Fails closed with clear error, no altered source or output | NOT RUN |
| QA-PDF-06 | Truncated/corrupt/non-PDF input | Fails closed, no app crash, no misleading exported file | NOT RUN |
| QA-PDF-07 | 16 MiB limit, large page count, invalid sequence | Limits enforced before risky allocations; no partial output | NOT RUN |
| QA-PDF-08 | PDF with forms, annotations, signatures, attachments | Unsupported/altered fidelity visibly documented; no claim of preserved signature | NOT RUN |
| QA-PDF-09 | JPX/JPEG2000 image PDF | Unsupported imagery documented; no silent claim of lossless output | NOT RUN |
| QA-PDF-10 | Cancel chooser or save; low storage; rapid repeated requests | No data loss or original mutation, controlled error and memory | NOT RUN |
| QA-PDF-11 | Regular Play/default APK | Toolbox button absent; unreviewed engine cannot be exposed | NOT RUN |
| QA-PDF-12 | Distribution audit | Apache-2.0 PDFBox notice and applicable Bouncy Castle license notices shipped; resolved transitive versions and vulnerabilities checked | NOT RUN |

## Evidence and signoff

For each executed row: source file descriptor and SHA, expected/actual page count, independent reader screenshot (with synthetic documents), output SHA, device log excerpt stripped of content, PASS/FAIL, tester and date. Failed cases must create a regression issue and block feature enablement.

Avoid storing PDF contents, document text, original paths or personal information in CI/GitHub logs. No code-review comment or green Flutter CI result substitutes for this signoff.

The dark-launch feature flag may be changed to production-enabled **only after all applicable rows pass** and security/license review is recorded. Password locking and irreversible PDF object redaction are explicitly out of scope.
