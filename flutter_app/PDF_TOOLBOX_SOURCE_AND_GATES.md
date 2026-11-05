# PDF Toolbox — license and release verification gates

Implementation scope: Android-only offline operations on copies: page-range extract, merge, rotate, reorder. Source PDF is read from immutable SHA-addressed Notes attachment storage and never modified. Output is exported only after an explicit user choice.

Upstream engine: [TomRoush/PdfBox-Android](https://github.com/TomRoush/PdfBox-Android), Maven coordinate `com.tom-roush:pdfbox-android:2.0.27.0`, Apache License 2.0. Review upstream LICENSE/NOTICE plus the transitive dependency inventory before distribution; preserve applicable copyright and notices in released app documentation.

Runtime boundaries: maximum 16 MiB per input PDF, 200 total pages, 32 MiB output. Encrypted/invalid files fail closed. The output file is newly constructed and not byte-identical to source; signatures, forms, JavaScript, media, annotations and embedded attachments may be altered or dropped. Do not promise universal fidelity.

**Not implemented:** password lock/protect, PDF-object redaction, secure removal of hidden content, iOS/Web PDF editing. The Privacy Shield feature handles reviewed *text copies* only; it is not PDF sanitization.

Release gates still required: Android device trials with multi-page, image-only, forms, signed/encrypted, malformed and large PDFs; check page order, visual fidelity, no original write, cancellation and memory use; verify APK delta, license compliance, store publication terms and recovery. A passing Flutter CI/APK build does not certify these behaviors.
