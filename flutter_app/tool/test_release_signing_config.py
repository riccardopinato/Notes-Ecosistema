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


if __name__ == "__main__":
    unittest.main()
