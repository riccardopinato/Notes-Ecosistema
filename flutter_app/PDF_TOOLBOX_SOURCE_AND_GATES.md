# PDF Toolbox — license and release verification gates

Implementation scope: Android-only offline operations on copies: page-range extract, merge, rotate, reorder. Source PDF is read from immutable SHA-addressed Notes attachment storage and never modified. Output is exported only after an explicit user choice.

Upstream engine: [TomRoush/PdfBox-Android](https://github.com/TomRoush/PdfBox-Android), Maven coordinate `com.tom-roush:pdfbox-android:2.0.27.0`, Apache License 2.0. Review upstream LICENSE/NOTICE plus the transitive dependency inventory before distribution; preserve applicable copyright and notices in released app documentation.

Runtime boundaries: maximum 16 MiB per input PDF, 200 total pages, 32 MiB output. Encrypted/invalid files fail closed. The output file is newly constructed and not byte-identical to source; signatures, forms, JavaScript, media, annotations and embedded attachments may be altered or dropped. Do not promise universal fidelity.

**Not implemented:** password lock/protect, PDF-object redaction, secure removal of hidden content, iOS/Web PDF editing. The Privacy Shield feature handles reviewed *text copies* only; it is not PDF sanitization.

Release gates still required: Android device trials with multi-page, image-only, forms, signed/encrypted, malformed and large PDFs; check page order, visual fidelity, no original write, cancellation and memory use; verify APK delta, license compliance, store publication terms and recovery. A passing Flutter CI/APK build does not certify these behaviors.

## Controlled exposure (2026-11-05)

The app now uses a **dark launch**: `NOTES_ENABLE_PDF_TOOLBOX` defaults to `false` in all normal builds. To expose the button in an isolated test build, compile `flutter build apk --debug --dart-define=NOTES_ENABLE_PDF_TOOLBOX=true`; GitHub Flutter Port CI additionally uploads a `Notes-PDF-Toolbox-QA-debug` artifact and the device test protocol for this PR. The ordinary release APKs and Play AAB do not enable the function.

The upstream PDFBox POM resolves Bouncy Castle 1.72 for `bcprov`, `bcpkix`, and `bcutil`. The generated Android build now requests the 1.86 maintenance line for those `-jdk15to18` modules, and CI checks the resolved release runtime graph; **the new pin is not certified until the exact-head CI is green**.

The remaining release gate is tracked in GitHub issue **#70** and `flutter_app/PDF_TOOLBOX_DEVICE_QA.md`. The code may be integrated with the function off; **enabling it for users or publishing a build that exposes PDF editing** requires physical Android QA, license/NOTICE distribution verification, vulnerable dependency review and separate approval.
