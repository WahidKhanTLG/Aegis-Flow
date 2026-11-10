"""Exercise membership, staging isolation and refusal behavior without Salesforce."""

from contextlib import contextmanager
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
module_spec = importlib.util.spec_from_file_location('managed', ROOT / 'scripts/prepare_managed_source.py')
managed = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(managed)


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory(prefix='aegis-managed-test-') as directory:
        base = Path(directory).resolve()
        root = base / 'source'
        root.mkdir()
        for folder in ['force-app', 'packaging', 'manifest']:
            shutil.copytree(ROOT / folder, root / folder)
        yield root, base / 'staged'


class ManagedSourceTests(unittest.TestCase):
    def test_validated_staging_is_exact_and_does_not_mutate_source(self):
        with fixture() as (root, output):
            permission = root / 'force-app/main/default/permissionsets/AEIR_Product_Admin.permissionset-meta.xml'
            before = permission.read_bytes()
            result = managed.stage(output, 'testns', root)
            self.assertFalse(result['packageCreated'])
            self.assertFalse(result['namespaceRegistrationVerified'])
            self.assertEqual(json.loads((output / 'sfdx-project.json').read_text())['namespace'], 'testns')
            self.assertEqual(permission.read_bytes(), before)
            self.assertNotIn(b'Account.Tax_Code__c', (output / permission.relative_to(root)).read_bytes())
            staged = {p.relative_to(output).as_posix() for p in (output / 'force-app').rglob('*') if p.is_file()}
            self.assertEqual(staged, set(result['files']))
            self.assertFalse(any('__tests__' in path or 'Aegis_Test_Order_' in path or 'standard__Lightning' in path for path in staged))
            self.assertFalse((output / '.sf').exists())

    def test_namespace_is_explicit_and_rejects_injection(self):
        for value in ['', '../x', 'abc/def', ' x', '1abc', 'a__b', 'abcdefghijklmnop']:
            with self.assertRaises(ValueError):
                managed.namespace_value(value)
        self.assertEqual(managed.namespace_value('my_np'), 'my_np')

    def test_existing_directory_is_not_overwritten(self):
        with fixture() as (root, output):
            output.mkdir()
            sentinel = output / 'preserve.txt'
            sentinel.write_text('User work')
            with self.assertRaises(ValueError):
                managed.stage(output, 'testns', root)
            self.assertEqual(sentinel.read_text(), 'User work')

    def test_unclassified_metadata_is_rejected(self):
        with fixture() as (root, _):
            (root / 'force-app/main/default/classes/Unreviewed.cls').write_text('public class Unreviewed {}')
            with self.assertRaisesRegex(ValueError, 'Unclassified'):
                managed.check(root)

    def test_existing_macos_metadata_is_ignored_and_never_staged(self):
        with fixture() as (root, output):
            junk = root / 'force-app/main/default/.DS_Store'
            junk.write_bytes(b'Existing OS metadata')
            managed.check(root)
            managed.stage(output, 'testns', root)
            self.assertEqual(junk.read_bytes(), b'Existing OS metadata')
            self.assertFalse((output / junk.relative_to(root)).exists())

    def test_metadata_symlink_is_rejected(self):
        with fixture() as (root, output):
            path = root / 'force-app/main/default/classes/AEIR_RetryHandler.cls'
            outside = output.parent / 'outside.cls'
            outside.write_bytes(path.read_bytes())
            path.unlink()
            path.symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'Symlinked'):
                managed.check(root)

    def test_subscriber_api_visibility_regression_is_rejected(self):
        with fixture() as (root, _):
            path = root / 'force-app/main/default/classes/AEIR_GetErrorContextAction.cls'
            path.write_text(path.read_text().replace('global static List<Response>', 'public static List<Response>'))
            with self.assertRaisesRegex(ValueError, 'method must be global'):
                managed.check(root)

    def test_membership_traversal_is_rejected(self):
        with fixture() as (root, _):
            path = root / 'packaging/managed-source-files.json'
            spec = json.loads(path.read_text())
            spec['files'].append('force-app/main/default/../../outside')
            path.write_text(json.dumps(spec))
            with self.assertRaisesRegex(ValueError, 'within product metadata'):
                managed.check(root)


if __name__ == '__main__':
    unittest.main()
