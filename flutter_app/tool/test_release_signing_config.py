"""Pure parser regressions for manual production signing configuration."""

import unittest

from configure_release_signing import (
    DEBUG_CONFIG,
    PRODUCTION_CONFIG,
    configure_gradle,
)


class ConfigureReleaseSigningTests(unittest.TestCase):
    def setUp(self):
        self.template = (
            'plugins { id("com.android.application") }\n'
            'android {\n'
            '    defaultConfig { applicationId = "it.notes.ecosystem.lymlyc" }\n'
            '    buildTypes {\n'
            '        release {\n'
            f'            {DEBUG_CONFIG}\n'
            '        }\n'
            '    }\n'
            '}\n'
        )

    def test_explicit_release_alias_replaces_only_debug_fallback(self):
        updated = configure_gradle(self.template)
        self.assertIn(PRODUCTION_CONFIG, updated)
        self.assertIn('create("notesProduction")', updated)
        self.assertNotIn(DEBUG_CONFIG, updated)
        self.assertEqual(updated.count('create("notesProduction")'), 1)
        self.assertIn('it.notes.ecosystem.lymlyc', updated)
        self.assertIn('System.getenv("NOTES_SIGNING_KEYSTORE_FILE")', updated)
        self.assertIn('System.getenv("NOTES_SIGNING_STORE_PASSWORD")', updated)

    def test_refuses_unexpected_or_duplicate_signing(self):
        with self.assertRaises(ValueError):
            configure_gradle('android {\n buildTypes {} }\n')
        with self.assertRaises(ValueError):
            configure_gradle(self.template.replace(DEBUG_CONFIG, ''))
        with self.assertRaises(ValueError):
            configure_gradle(self.template.replace(DEBUG_CONFIG, DEBUG_CONFIG * 2))
        with self.assertRaises(ValueError):
            configure_gradle(self.template + 'create("notesProduction")\n')


from signing_upgrade_preflight import APP_ID, UpgradeEvidence, verify_upgrade

class UpgradePreflightTests(unittest.TestCase):
    installed = "a" * 64
    candidate = "b" * 64

    def evidence(self, **updates):
        values = dict(
            installed_package=APP_ID,
            candidate_package=APP_ID,
            installed_cert=self.installed,
            candidate_cert=self.installed,
            installed_code=74,
            candidate_code=75,
            candidate_subject="CN=Notes Release",
            channel="direct",
        )
        values.update(updates)
        return UpgradeEvidence(**values)

    def test_direct_same_key_and_increment_is_only_preflight(self):
        self.assertEqual(
            verify_upgrade(self.evidence()), "DIRECT_CERT_AND_VERSION_MATCH"
        )

    def test_incompatible_existing_debug_key_refuses_update(self):
        with self.assertRaisesRegex(ValueError, "INCOMPATIBLE_INSTALLED_CERTIFICATE"):
            verify_upgrade(self.evidence(candidate_cert=self.candidate))

    def test_debug_identity_and_nonincreasing_version_fail_closed(self):
        for changes in (
            dict(candidate_subject="C=US,O=Android,CN=Android Debug"),
            dict(candidate_code=74),
            dict(candidate_code=0),
            dict(candidate_package="it.notes.ecosystem.lymlyc.ui5qa"),
            dict(installed_cert="unknown"),
        ):
            with self.subTest(changes=changes):
                with self.assertRaises(ValueError):
                    verify_upgrade(self.evidence(**changes))

    def test_play_requires_delivery_signing_cert_not_upload_key(self):
        evidence = self.evidence(
            channel="play",
            candidate_cert=self.candidate,
            play_app_signing_cert=self.installed,
        )
        self.assertEqual(
            verify_upgrade(evidence), "PLAY_DELIVERY_CERT_AND_VERSION_MATCH"
        )
        with self.assertRaisesRegex(ValueError, "MISSING_PLAY_APP_SIGNING_CERTIFICATE"):
            verify_upgrade(self.evidence(channel="play", candidate_cert=self.candidate))
        with self.assertRaisesRegex(ValueError, "INCOMPATIBLE_PLAY_APP_SIGNING_CERTIFICATE"):
            verify_upgrade(self.evidence(
                channel="play",
                candidate_cert=self.candidate,
                play_app_signing_cert=self.candidate,
            ))

    def test_reject_unrecognized_channel_and_unexpected_play_certificate(self):
        with self.assertRaises(ValueError):
            verify_upgrade(self.evidence(channel="unknown"))
        with self.assertRaises(ValueError):
            verify_upgrade(self.evidence(play_app_signing_cert=self.installed))




if __name__ == "__main__":
    unittest.main()
