# Master Prompt v5 Compliance — 0.32.0

## Source of truth and delivery model

From 0.32 onward Notes-Ecosistema follows the consolidated utility master prompt v5:

- GitHub repository is the single source of truth;
- main must remain stable;
- development happens on a dedicated branch and pull request;
- no merge before every required gate is green;
- CI does not weaken tests to obtain a green result;
- the final Android delivery is one lightweight ARM64 release APK;
- debug/universal APKs are internal only unless explicitly requested.

## Pinned production toolchain

CI is pinned to:

- Ubuntu 24.04 runner;
- Flutter 3.47.5 stable;
- Dart 3.13.4 through the pinned Flutter SDK;
- Java 17;
- Android emulator API 35 x86_64 for the release smoke gate.

Flutter 3.47.5 is the stable release used as the project baseline for this step.

## Persistent Android signing

Release APKs must use a persistent private signing key stored outside the
repository.

Required GitHub Actions repository secrets:

- NOTES_ANDROID_KEYSTORE_BASE64
- NOTES_ANDROID_STORE_PASSWORD
- NOTES_ANDROID_KEY_ALIAS
- NOTES_ANDROID_KEY_PASSWORD

The workflow fails before building the release if any signing secret is absent.

The private key, passwords and keystore are never committed to the repository.

## Required close-step gate

A 0.32+ step is considered complete only after:

1. dart format check;
2. flutter analyze;
3. unit/widget tests;
4. release split-per-ABI build;
5. Android release signature verification;
6. ARM64 size regression gate;
7. installation of the release APK in a real Android emulator;
8. real app launch;
9. functional smoke flow;
10. persisted-note verification;
11. UI screenshot capture;
12. logcat capture;
13. crash/ANR scan;
14. obfuscation symbol upload;
15. ARM64 release artifact generation.

The emulator test runs against the release x86_64 APK because the GitHub-hosted
emulator is x86_64. The APK distributed to the user remains ARM64 only.

## Functional release smoke

The automated Android smoke flow performs the following operations against a
clean app installation:

- launch Notes;
- verify Home renders;
- navigate to Shared Spaces;
- return Home;
- open the create menu;
- create a real note;
- enter title and body;
- save it to SQLite;
- navigate to Note;
- verify the saved note is visible;
- verify the app process remains alive;
- capture a screenshot;
- capture UI hierarchy;
- capture logcat;
- fail on FATAL EXCEPTION / app ANR signatures.

Evidence is retained as an internal CI artifact.

## Release size and optimization

The existing 38 MiB ARM64 regression gate remains mandatory.

Release build keeps:

- R8/minify;
- resource shrinking;
- Dart obfuscation;
- split debug symbols.

Only the ARM64 release APK is exposed as the normal installable output.

## Direct APK delivery

On a successful main build the workflow creates/updates a GitHub Release for the
pubspec version and uploads:

Notes-Ecosistema-<version>-arm64-v8a.apk

This provides a direct .apk release asset rather than forcing the user to
extract an Actions artifact ZIP.

## Web

The web preview remains built from the same repository and pinned Flutter
toolchain.

Automatic GitHub Pages deployment remains conditioned on repository Pages being
enabled. The build itself is still a CI gate; deployment is not falsely reported
as successful when Pages administration is unavailable to the GitHub App.

## Merge policy

The 0.32 branch must remain unmerged while any mandatory gate is red.

After a green PR gate, the branch can be merged to main. The main build then
publishes the direct ARM64 APK release asset and runs the web build/deploy flow.
