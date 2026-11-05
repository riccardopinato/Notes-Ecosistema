# Componenti terze parti

Notes Ecosistema 0.25.1 usa Flutter e dipendenze dichiarate in `flutter_app/pubspec.yaml`.

Tra i componenti principali sono presenti Flutter/Riverpod, sqflite, file_picker, path_provider, crypto, archive, image_picker, record e plugin Google ML Kit per scanner documenti e riconoscimento testo.

Le dipendenze mantengono le rispettive licenze upstream. Nessun codice della precedente linea Kotlin viene compilato nella linea Flutter canonica; il sorgente storico resta disponibile nella branch `kotlin-legacy-0.25`.

## PDF Toolbox (Android, QA-only until signoff)

- **PdfBox-Android** `com.tom-roush:pdfbox-android:2.0.27.0`, by Tom Roush and contributors. License: **Apache License 2.0**. Source and license: https://github.com/TomRoush/PdfBox-Android and https://www.apache.org/licenses/LICENSE-2.0 . Preserve upstream copyright and any applicable NOTICE text upon redistribution.
- **Bouncy Castle Java**, transitive `bcprov-jdk15to18`, `bcpkix-jdk15to18`, `bcutil-jdk15to18` (PDFBox POM pins 1.72; the generated Android build requests the matching 1.86 line with a Gradle resolution rule). Copyright © The Legion of the Bouncy Castle Inc. License: **MIT-style Bouncy Castle License**. Official license: https://www.bouncycastle.org/licence.html .
- **Gemalto JP2Android** is NOT bundled. JPX/JPEG2000 PDF image fidelity is not certified; suppressing R8 warnings is not installing the optional decoder.

These references are a traceability record, not a substitute for distributing the full applicable license and copyright texts, preserving upstream NOTICE requirements, inspecting actual resolved Gradle dependency versions, and validating license disclosures in the distributed Play package. Final redistribution clearance is gated in `flutter_app/PDF_TOOLBOX_DEVICE_QA.md`.
