import unittest

from build_repro_evidence import (
    compare_manifests,
    make_manifest,
    runtime_inventory,
    template_hashes,
)


class ReproducibilityEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.flutter = b"Flutter 3.47.9 . stable\nDart 3.11\n"
        self.lock = b"# lockfile pinned\n"
        self.template = (
            (b"a" * 64) +
            b"  android/gradle/wrapper/gradle-wrapper.properties\n" +
            (b"b" * 64) +
            b"  android/settings.gradle.kts\n"
        )
        self.gradle = (
            b"> Task :app:dependencies\n"
            b"+--- androidx.work:work-runtime:2.11.2\n"
            b"|    \\--- org.bouncycastle:bcprov-jdk15to18:1.72 -> 1.86 (*)\n"
            b"BUILD SUCCESSFUL in 53s\n"
        )

    def test_normalizes_report_without_runner_duration_or_duplicates(self):
        one = runtime_inventory(self.gradle.decode())
        two = runtime_inventory(
            self.gradle.decode().replace("53s", "19s") +
            "\\--- androidx.work:work-runtime:2.11.2 (c)\n"
        )
        self.assertEqual(one, two)
        self.assertIn("org.bouncycastle:bcprov-jdk15to18:1.72 -> 1.86", one)

    def test_manifest_is_stable_for_identical_dependency_resolution(self):
        a = make_manifest(self.flutter, self.lock, self.template, self.gradle)
        b = make_manifest(
            self.flutter, self.lock, self.template,
            self.gradle.replace(b"53s", b"100s"),
        )
        self.assertEqual(compare_manifests(a, b), [])

    def test_detects_drift_from_flutter_lock_template_or_gradle(self):
        original = make_manifest(
            self.flutter, self.lock, self.template, self.gradle
        )
        for changed in (
            (self.flutter, b"different lock", self.template, self.gradle),
            (self.flutter, self.lock,
             self.template.replace(b"a" * 64, b"c" * 64), self.gradle),
            (self.flutter, self.lock, self.template,
             self.gradle.replace(b"1.86", b"1.85")),
        ):
            with self.subTest(changed=changed):
                observed = make_manifest(*changed)
                self.assertTrue(compare_manifests(original, observed))

    def test_rejects_unsupported_versions_and_missing_evidence(self):
        with self.assertRaisesRegex(ValueError, "FLUTTER_VERSION_PIN_MISMATCH"):
            make_manifest(
                b"Flutter 3.48.0\n", self.lock, self.template, self.gradle
            )
        with self.assertRaises(ValueError):
            template_hashes(("a" * 64) + "  unknown.path")
        with self.assertRaises(ValueError):
            runtime_inventory("BUILD SUCCESSFUL in 4s")
        with self.assertRaises(ValueError):
            compare_manifests({}, {})
