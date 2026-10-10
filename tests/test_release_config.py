import base64
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('release_config', Path(__file__).parents[1] / 'scripts/verify_release_config.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseConfigTests(unittest.TestCase):
    def values(self):
        return dict(CONFIGURATION='Release', MAFIA_PRODUCTION_CONVEX_HOST='handsome-tiger-460.eu-west-1.convex.cloud',
                    MAFIA_PRODUCTION_CLERK_PUBLISHABLE_KEY='pk_live_' + base64.b64encode(b'clerk.qa.example$').decode().rstrip('='),
                    MAFIA_CLERK_FRONTEND_HOST='clerk.qa.example')

    def test_production_configuration_passes(self):
        module.validate(self.values())

    def test_debug_configuration_needs_no_production_key(self):
        module.validate(dict(CONFIGURATION='Debug'))

    def test_missing_test_or_malformed_keys_and_wrong_domains_fail(self):
        for field, value in [('MAFIA_PRODUCTION_CLERK_PUBLISHABLE_KEY', ''),
                             ('MAFIA_PRODUCTION_CLERK_PUBLISHABLE_KEY', 'pk_test_key'),
                             ('MAFIA_PRODUCTION_CLERK_PUBLISHABLE_KEY', 'pk_live_invalid'),
                             ('MAFIA_PRODUCTION_CONVEX_HOST', 'energized-herring-345.eu-west-1.convex.cloud'),
                             ('MAFIA_CLERK_FRONTEND_HOST', 'wrong.example')]:
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                module.validate(self.values() | {field: value})


if __name__ == '__main__':
    unittest.main()
