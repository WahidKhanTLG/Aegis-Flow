"""Validate or stage reviewed metadata locally. Never invoke Salesforce or create a package."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}
ET.register_namespace('', NS['m'])


def namespace_value(value):
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,14}', value) or '__' in value:
        raise ValueError('Supply the team-selected 1-15 character namespace; no default is selected.')
    return value


def definition(root):
    spec = json.loads((root / 'packaging/managed-source-files.json').read_text())
    files = spec['files']
    all_paths = files + list(spec['excluded'])
    if len(all_paths) != len(set(all_paths)):
        raise ValueError('Duplicate or conflicting package membership.')
    for name in all_paths:
        parts = Path(name).parts
        if not name.startswith('force-app/main/default/') or '..' in parts:
            raise ValueError('Package membership must stay within product metadata.')
        if Path(name).name == '.DS_Store':
            raise ValueError('OS metadata must never be a managed-source member.')
        path = root / name
        if any(parent.is_symlink() for parent in [path, *path.parents] if parent != root.parent):
            raise ValueError('Symlinked package metadata is unsupported.')
        if not path.is_file():
            raise ValueError('Missing reviewed metadata: ' + name)
    actual = {p.relative_to(root).as_posix() for p in (root / 'force-app/main/default').rglob('*')
              if p.is_file() and p.name != '.DS_Store'}
    if actual != set(all_paths):
        raise ValueError('Unclassified metadata: ' + ', '.join(sorted(actual ^ set(all_paths))))
    return spec


def content(root, spec, name):
    raw = (root / name).read_bytes()
    for change in spec['transforms']:
        if change['path'] != name:
            continue
        tree = ET.fromstring(raw)
        nodes = [node for node in tree.findall('m:fieldPermissions', NS)
                 if node.findtext('m:field', namespaces=NS) == change['removeFieldPermission']]
        if len(nodes) != 1:
            raise ValueError('Reviewed permission transform no longer matches its source.')
        tree.remove(nodes[0])
        ET.indent(tree, space='    ')
        raw = ET.tostring(tree, encoding='utf-8', xml_declaration=True) + b'\n'
    return raw


def check(root=ROOT):
    spec = definition(root)
    metadata = root / 'force-app/main/default'
    action_apis = []
    for path in sorted((metadata / 'classes').glob('*.cls')):
        source = path.read_text()
        if '@InvocableMethod' not in source:
            continue
        if not re.search(r'global with sharing class ' + path.stem + r'\b', source):
            raise ValueError('Subscriber action class must be global: ' + path.name)
        entry = source[source.index('@InvocableMethod'):].split('{', 1)[0]
        if not re.search(r'global static List<', entry):
            raise ValueError('Subscriber action method must be global: ' + path.name)
        for wrapper in ['Request', 'Response']:
            if re.search(r'\bclass ' + wrapper + r'\b', source):
                if f'global class {wrapper}' not in source or f'global {wrapper}()' not in source:
                    raise ValueError('Subscriber wrapper/constructor must be global: ' + path.name)
        for variable in source.split('@InvocableVariable')[1:]:
            if not re.search(r'\bglobal\s+(String|Id|Boolean|Integer|Decimal)\s+\w+\s*;', variable.split(';', 1)[0] + ';'):
                raise ValueError('Subscriber action variable must be global: ' + path.name)
        action_apis.append(path.stem)
    if len(action_apis) != 9:
        raise ValueError('Review the subscriber action inventory before changing the nine-action contract.')
    for path in (metadata / 'lwc').rglob('*.html'):
        if '__tests__' not in path.parts and re.search(r'(?:object-api-name|field-name)="[A-Za-z0-9_]+__c"', path.read_text()):
            raise ValueError('Use schema references for package object/field bindings: ' + path.name)
    monitor = (metadata / 'lwc/aegisHeadlessMonitor/aegisHeadlessMonitor.js').read_text()
    if "'/event/Aegis_User_Alert__e'" in monitor or 'DEFAULT_ALERT_CHANNEL' in monitor:
        raise ValueError('Do not guess an unmanaged custom-event fallback.')
    for name in spec['files']:
        if '__tests__' in Path(name).parts or 'Aegis_Test_Order_' in name or '/applications/standard__' in name:
            raise ValueError('Managed core contains development or subscriber-specific metadata: ' + name)
        if name.endswith('.xml'):
            ET.fromstring(content(root, spec, name))
        if '/PlatformEventSubscriberConfigs/' in name:
            tree = ET.fromstring(content(root, spec, name))
            if tree.find('m:user', NS) is not None:
                raise ValueError('Subscriber identities must be bound by the installing administrator.')
    permission = content(root, spec, 'force-app/main/default/permissionsets/AEIR_Product_Admin.permissionset-meta.xml')
    if b'Account.Tax_Code__c' in permission:
        raise ValueError('Managed Product Admin must not reference excluded sample schema.')
    return {'status': 'PASS', 'includedMetadataFiles': len(spec['files']),
            'excludedFiles': len(spec['excluded']), 'subscriberActionApis': action_apis,
            'transforms': spec['transforms'], 'salesforceCommands': 0,
            'namespacedCompilationProven': False, 'packageCreated': False}


def stage(output, namespace, root=ROOT):
    namespace_value(namespace)
    result = check(root)
    spec = definition(root)
    output = Path(output).resolve()
    if output.exists() or output == root or root in output.parents:
        raise ValueError('Choose a fresh staging directory outside the source project; existing directories are never overwritten.')
    # Render every input before creating any output.
    rendered = {name: content(root, spec, name) for name in spec['files']}
    project = {'packageDirectories': [{'path': 'force-app', 'default': True}],
               'name': 'aegis-flow-managed-source', 'namespace': namespace,
               'sourceApiVersion': spec['sourceApiVersion'], 'sfdcLoginUrl': 'https://login.salesforce.com'}
    manifest = ET.parse(root / 'manifest/package.xml')
    excluded_members = {
        'CustomApplication': {'standard__LightningSales', 'standard__LightningSalesConsole', 'standard__LightningService'},
        'FlexiPage': {'LightningSales_UtilityBar', 'LightningSalesConsole_UtilityBar', 'LightningService_UtilityBar'},
        'Layout': {'Contact-Contact Layout'}, 'CustomField': {'Account.Tax_Code__c'},
        'PermissionSet': {'AEIR_Sample_Account_Remediation'},
        'CustomMetadata': {'Remediation_Action_Setting.UPDATE_ACCOUNT_TAX_CODE', 'Retry_Handler.ORDER_TAX_RECALCULATION'}
    }
    for group in manifest.getroot().findall('m:types', NS):
        remove = excluded_members.get(group.findtext('m:name', namespaces=NS), set())
        for node in list(group.findall('m:members', NS)):
            if node.text in remove:
                group.remove(node)
    output.mkdir(parents=True)
    for name, raw in rendered.items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
    (output / 'sfdx-project.json').write_text(json.dumps(project, indent=2) + '\n')
    (output / 'manifest').mkdir()
    manifest.write(output / 'manifest/package.xml', encoding='utf-8', xml_declaration=True)
    result['namespace'] = namespace
    result['namespaceRegistrationVerified'] = False
    result['files'] = {name: hashlib.sha256(raw).hexdigest() for name, raw in rendered.items()}
    (output / 'managed-source-manifest.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--stage', type=Path)
    parser.add_argument('--namespace')
    args = parser.parse_args()
    try:
        if args.stage:
            if not args.namespace:
                raise ValueError('A staging operation needs an explicitly selected namespace.')
            result = stage(args.stage, args.namespace)
        elif args.namespace:
            raise ValueError('A namespace is used only with a fresh local staging directory.')
        else:
            result = check()
        print(json.dumps({key: value for key, value in result.items() if key != 'files'}, indent=2))
        return 0
    except (ValueError, OSError, ET.ParseError, KeyError) as error:
        print(json.dumps({'status': 'FAIL', 'error': str(error)}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
