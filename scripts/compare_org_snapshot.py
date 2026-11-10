#!/usr/bin/env python3
"""Compare manifest-scoped local Salesforce source with a retrieved DX snapshot.

Read-only: no Salesforce commands, authentication, network, source changes or raw
diff output. Only the requested report is written. Regenerate the explicit release
manifest with generate_manifest.py when adding metadata types/components.

Usage:
  python3 scripts/compare_org_snapshot.py --org-source /path/to/force-app/main/default \
    --output output/development/YYYY-MM-DD/parity.json

Exit 0 means semantic parity with the narrowly listed org configuration allowances;
exit 1 means an unexpected difference, missing file, unsupported scope or read error.
This verifies the supplied snapshot, not the current live org or runtime acceptance.
"""

import argparse
from collections import Counter
import copy
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
NS = 'http://soap.sforce.com/2006/04/metadata'
XSI = 'http://www.w3.org/2001/XMLSchema-instance'
XSD = 'http://www.w3.org/2001/XMLSchema'
M = '{' + NS + '}'
SINGLE_FILES = {
    'CustomApplication': ('applications', '.app-meta.xml'),
    'CustomMetadata': ('customMetadata', '.md-meta.xml'),
    'CustomPermission': ('customPermissions', '.customPermission-meta.xml'),
    'CustomTab': ('tabs', '.tab-meta.xml'),
    'FlexiPage': ('flexipages', '.flexipage-meta.xml'),
    'Flow': ('flows', '.flow-meta.xml'),
    'Layout': ('layouts', '.layout-meta.xml'),
    'PermissionSet': ('permissionsets', '.permissionset-meta.xml'),
    'PlatformEventSubscriberConfig': ('PlatformEventSubscriberConfigs', '.platformEventSubscriberConfig-meta.xml'),
    'QuickAction': ('quickActions', '.quickAction-meta.xml'),
}
RESOURCE_ALIASES = {'AegisFlowBrand': ('resource', 'jpeg'), 'AegisFlowLogo': ('resource', 'png')}
FEATURE_OVERRIDES = {'Feature_Flag.AUTO_DIAGNOSIS', 'Feature_Flag.GOVERNED_REMEDIATION'}
SUBSCRIBERS = {
    'AEIR_AgentDiagnosisRequestedEventTrigger', 'AEIR_BatchApexErrorEventTrigger',
    'AEIR_DiagnosticSessionRequestTrigger', 'AEIR_ErrorCapturedEventTrigger',
    'AEIR_EscalationRequestedEventTrigger',
}
PERMISSION_ROWS = {
    'applicationVisibilities': 'application', 'classAccesses': 'apexClass',
    'customMetadataTypeAccesses': 'name', 'customPermissions': 'name',
    'customSettingAccesses': 'name', 'externalCredentialPrincipalAccesses': 'externalCredentialPrincipal',
    'fieldPermissions': 'field', 'flowAccesses': 'flow', 'objectPermissions': 'object',
    'pageAccesses': 'apexPage', 'recordTypeVisibilities': 'recordType',
    'tabSettings': 'tab', 'userPermissions': 'name',
}
PERMISSION_SCALARS = {'description', 'label', 'hasActivationRequired', 'license'}
TOOLING_NAMES = {'.DS_Store', '.eslintrc', '.eslintrc.json', 'jsconfig.json', 'tsconfig.json'}


class ComparisonError(Exception):
    """Messages must be fixed descriptions: never put metadata values in them."""


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_relative(path):
    return path.as_posix()


def excluded(path):
    return '__tests__' in path.parts or path.name in TOOLING_NAMES


def manifest_members(path):
    try:
        package = ET.fromstring(path.read_bytes())
    except (OSError, ET.ParseError):
        raise ComparisonError('The explicit manifest could not be read or parsed.')
    if package.tag != M + 'Package':
        raise ComparisonError('The manifest must be a Salesforce metadata Package.')
    result = {}
    for group in package.findall(M + 'types'):
        kind = group.findtext(M + 'name')
        members = [node.text for node in group.findall(M + 'members')]
        if not kind or kind in result or not members or len(set(members)) != len(members):
            raise ComparisonError('Manifest groups and members must be unique and nonempty.')
        if any(not member or '*' in member or '/' in member or '\\' in member or '..' in member for member in members):
            raise ComparisonError('Use explicit manifest members without wildcards or traversal.')
        result[kind] = sorted(members)
    return result


def inventory(members, local, snapshot):
    units = {}

    def add(kind, member, logical, alternatives=None):
        previous = units.get(logical)
        if previous and previous['type'] not in {kind, 'CustomObjectChild'}:
            raise ComparisonError('Manifest components resolve to an ambiguous source path.')
        units[logical] = {'type': kind, 'member': member, 'path': logical,
                          'alternatives': alternatives or [logical]}

    for kind, names in members.items():
        for member in names:
            if kind in SINGLE_FILES:
                folder, suffix = SINGLE_FILES[kind]
                add(kind, member, f'{folder}/{member}{suffix}')
            elif kind in {'ApexClass', 'ApexTrigger'}:
                folder, suffix = ('classes', '.cls') if kind == 'ApexClass' else ('triggers', '.trigger')
                add(kind, member, f'{folder}/{member}{suffix}')
                add(kind, member, f'{folder}/{member}{suffix}-meta.xml')
            elif kind in {'CustomField', 'ListView'}:
                if '.' not in member:
                    raise ComparisonError('Object child members require an object-qualified name.')
                owner, child = member.split('.', 1)
                folder, suffix = ('fields', '.field-meta.xml') if kind == 'CustomField' else ('listViews', '.listView-meta.xml')
                add(kind, member, f'objects/{owner}/{folder}/{child}{suffix}')
            elif kind == 'CustomObject':
                prefix = Path('objects') / member
                add(kind, member, f'{prefix.as_posix()}/{member}.object-meta.xml')
                # Retrieving a selected CustomObject also returns its children. An
                # unexpected org-only field on that object must not disappear here.
                children = {p.relative_to(root).as_posix() for root in (local, snapshot)
                            for p in (root / prefix).rglob('*') if p.is_file() and not excluded(p)}
                for child in sorted(children):
                    if child not in units:
                        pieces = Path(child).parts
                        child_kind = {'fields': 'CustomField', 'listViews': 'ListView'}.get(pieces[2], 'CustomObjectChild') if len(pieces) > 3 else kind
                        add(child_kind, member, child)
            elif kind == 'LightningComponentBundle':
                prefix = Path('lwc') / member
                files = {p.relative_to(root).as_posix() for root in (local, snapshot)
                         for p in (root / prefix).rglob('*') if p.is_file() and not excluded(p)}
                files.add(f'lwc/{member}/{member}.js-meta.xml')
                for file in sorted(files):
                    add(kind, member, file)
            elif kind == 'StaticResource':
                add(kind, member, f'staticresources/{member}.resource-meta.xml')
                extensions = RESOURCE_ALIASES.get(member, ('resource',))
                add(kind, member, f'staticresources/{member}.resource',
                    [f'staticresources/{member}.{extension}' for extension in extensions])
            else:
                raise ComparisonError('Unsupported manifest metadata type; add explicit scope support first.')
    return units


def read_unit(root, unit):
    found = []
    for relative in unit['alternatives']:
        path = root / relative
        if path.is_symlink() or (path.exists() and not path.resolve().is_relative_to(root)):
            raise ComparisonError('A source file link escapes or replaces the selected source scope.')
        if path.is_file():
            found.append((relative, path.read_bytes()))
    if not found:
        return None
    if any(data != found[0][1] for _, data in found[1:]):
        raise ComparisonError('Static resource aliases contain different binary content.')
    return {'path': found[0][0], 'bytes': found[0][1], 'aliases': [name for name, _ in found]}


def parsed_xml(data):
    try:
        prefixes = {}
        for _, (prefix, uri) in ET.iterparse(io.BytesIO(data), events=('start-ns',)):
            if prefix in prefixes and prefixes[prefix] != uri:
                raise ComparisonError('XML namespace prefix rebinding requires explicit review.')
            prefixes[prefix] = uri
        root = ET.fromstring(data)
        for element in root.iter():
            key = '{' + XSI + '}type'
            if key in element.attrib and ':' in element.attrib[key]:
                prefix, name = element.attrib[key].split(':', 1)
                if prefix not in prefixes:
                    raise ComparisonError('An XML type namespace could not be resolved.')
                element.attrib[key] = '{' + prefixes[prefix] + '}' + name
        return root
    except ET.ParseError:
        raise ComparisonError('XML metadata could not be parsed.')


def children_named(root, name):
    return root.findall(M + name)


def plain_scalar(node):
    return not node.attrib and not list(node)


def remove_false_default(root, name, notes, rule):
    children = children_named(root, name)
    if len(children) > 1:
        raise ComparisonError('A scalar metadata default appears more than once.')
    if children and children[0].text in {'false', '0'} and not children[0].attrib and not list(children[0]):
        root.remove(children[0])
        notes.add(rule)


def numeric_value(text):
    try:
        value = Decimal(text.strip())
    except InvalidOperation:
        raise ComparisonError('Custom metadata contains an invalid numeric value.')
    if not value.is_finite():
        raise ComparisonError('Nonfinite custom metadata requires explicit review.')
    sign, digits, exponent = value.as_tuple()
    if not any(digits):
        return '0'
    digits = list(digits)
    while digits[-1] == 0:
        digits.pop()
        exponent += 1
    return json.dumps([sign, digits, exponent], separators=(',', ':'))


def normalize_xml(root, notes):
    if root.tag == M + 'PermissionSet':
        remove_false_default(root, 'hasActivationRequired', notes, 'permission-set-default-activation-false')
        identities = set()
        for child in root:
            tag = child.tag.removeprefix(M)
            if tag not in PERMISSION_ROWS and tag not in PERMISSION_SCALARS:
                raise ComparisonError('An unrecognized PermissionSet root element requires explicit review.')
            identity = (tag, child.findtext(M + PERMISSION_ROWS[tag])) if tag in PERMISSION_ROWS else (tag, '')
            if identity in identities or identity[1] is None:
                raise ComparisonError('PermissionSet rows/scalars must have unique identities.')
            identities.add(identity)
        # Salesforce deletes an object-permission record when every grant is false.
        # Normalize only the complete known shape; any enabled/unknown/attributed value remains significant.
        # https://developer.salesforce.com/docs/platform/object-reference/references/standard-objects/object-permissionset.html
        required_flags = {'allowCreate', 'allowDelete', 'allowEdit', 'allowRead', 'modifyAllRecords', 'viewAllRecords'}
        for row in list(root):
            names = [node.tag.removeprefix(M) for node in row]
            if (row.tag == M + 'objectPermissions' and not row.attrib
                    and len(names) == len(set(names))
                    and required_flags | {'object'} <= set(names)
                    and set(names) <= required_flags | {'object', 'viewAllFields'}
                    and all(plain_scalar(node) for node in row)
                    and (row.findtext(M + 'object') or '').strip()
                    and all(node.text in {'false', '0'} for node in row if node.tag != M + 'object')):
                root.remove(row)
                notes.add('permission-set-object-no-grants-row-omitted')
        before = list(root)
        root[:] = sorted(root, key=lambda child: (child.tag, child.findtext(M + PERMISSION_ROWS[child.tag.removeprefix(M)], '') if child.tag.removeprefix(M) in PERMISSION_ROWS else ''))
        if list(root) != before:
            notes.add('permission-set-root-set-order')
    elif root.tag == M + 'CustomField':
        # Retrieved inactive flags may be explicit while portable source omits them.
        # Only false/0 is equivalent: enabled values, attributes and duplicates stay significant.
        # https://developer.salesforce.com/docs/platform/api-metadata/references/meta-types/metadata-customfield.html
        for name in ('externalId', 'required', 'unique', 'caseSensitive', 'trackHistory', 'trackTrending'):
            remove_false_default(root, name, notes, 'custom-field-default-' + name + '-false')
    elif root.tag == M + 'CustomMetadata':
        rows = children_named(root, 'values')
        names = [row.findtext(M + 'field') for row in rows]
        if None in names or len(set(names)) != len(names):
            raise ComparisonError('Custom metadata value fields must be unique and named.')
        for row in rows:
            values = children_named(row, 'value')
            if len(values) != 1:
                raise ComparisonError('Custom metadata requires one value element per field.')
            value = values[0]
            value_type = value.get('{' + XSI + '}type')
            nil = value.get('{' + XSI + '}nil')
            if nil in {'true', '1'} and ((value.text is not None and value.text != '') or list(value)):
                raise ComparisonError('A nil custom metadata value contains content.')
            if not list(value) and (value.text is None or value.text == '') and (nil in {'true', '1'} or value_type in {None, '{' + XSD + '}string'}):
                if set(value.attrib) - {'{' + XSI + '}type', '{' + XSI + '}nil'}:
                    raise ComparisonError('Unrecognized empty custom metadata attributes require review.')
                # A retrieved CMT record can explicitly emit a nil value for a
                # schema field omitted by portable source. Both represent the
                # same currently empty stored value in a snapshot comparison.
                root.remove(row)
                notes.add('custom-metadata-empty-nil-omitted-equivalence')
            elif value_type == '{' + XSD + '}double' and value.text is not None:
                value.text = numeric_value(value.text)
                notes.add('custom-metadata-double-numeric-equivalence')
        ordered = iter(sorted(children_named(root, 'values'), key=lambda row: row.findtext(M + 'field')))
        before = list(root)
        root[:] = [next(ordered) if child.tag == M + 'values' else child for child in root]
        if list(root) != before:
            notes.add('custom-metadata-value-order')
    elif root.tag == M + 'PlatformEventSubscriberConfig':
        remove_false_default(root, 'isProtected', notes, 'subscriber-default-isProtected-false')
    return root


def canonical(element):
    content = element.text or ''
    if list(element) and not content.strip():
        content = ''
    tail = element.tail or ''
    if not tail.strip():
        tail = ''
    return (element.tag, tuple(sorted(element.attrib.items())), content,
            tuple(canonical(child) for child in element), tail)


def expected_configuration(unit, local, snapshot, notes):
    local, snapshot = copy.deepcopy(local), copy.deepcopy(snapshot)
    overrides = []
    if unit['type'] == 'CustomMetadata' and unit['member'] in FEATURE_OVERRIDES:
        left = [row.find(M + 'value') for row in children_named(local, 'values') if row.findtext(M + 'field') == 'Enabled__c']
        right = [row.find(M + 'value') for row in children_named(snapshot, 'values') if row.findtext(M + 'field') == 'Enabled__c']
        if len(left) == len(right) == 1 and left[0] is not None and right[0] is not None:
            if left[0].text == 'false' and right[0].text == 'true' and left[0].attrib == right[0].attrib:
                right[0].text = 'false'
                overrides.append({'field': 'Enabled__c', 'local': False, 'snapshot': True})
    if unit['type'] == 'PlatformEventSubscriberConfig':
        # Salesforce removes parallel subscription behavior for a single partition.
        # Only this exact pair is treated as a serializer default; no other key or
        # partition count, and no explicitly configured local value, is discarded.
        lp, lk = children_named(local, 'numPartitions'), children_named(local, 'partitionKey')
        rp, rk = children_named(snapshot, 'numPartitions'), children_named(snapshot, 'partitionKey')
        if (not lp and not lk and len(rp) == len(rk) == 1 and plain_scalar(rp[0]) and plain_scalar(rk[0])
                and rp[0].text == '1' and rk[0].text == 'EventUuid'):
            snapshot.remove(rp[0])
            snapshot.remove(rk[0])
            notes.add('subscriber-single-stream-serializer-defaults')
        if unit['member'] in SUBSCRIBERS:
            lu, ru = children_named(local, 'user'), children_named(snapshot, 'user')
            if (len(lu) <= 1 and len(ru) == 1 and plain_scalar(ru[0])
                    and (not lu or (plain_scalar(lu[0]) and not (lu[0].text or '').strip()))
                    and (ru[0].text or '').strip()):
                for node in lu:
                    local.remove(node)
                snapshot.remove(ru[0])
                overrides.append({'field': 'user', 'local': 'portable-unconfigured',
                                  'snapshot': 'configured-running-principal', 'valueRedacted': True})
    return local, snapshot, overrides


def compare_unit(unit, left, right):
    record = {'path': unit['path'], 'type': unit['type'], 'localPath': left['path'], 'snapshotPath': right['path']}
    notes = set()
    if unit['type'] == 'StaticResource' and not unit['path'].endswith('.xml'):
        category = 'binary'
        same = left['bytes'] == right['bytes']
        record['aliasesVerified'] = {'local': left['aliases'], 'snapshot': right['aliases']}
        status = 'exact' if same else 'unexpected'
    elif unit['path'].endswith('.xml'):
        category = 'metadata'
        if left['bytes'] == right['bytes']:
            status = 'exact'
        else:
            a = normalize_xml(parsed_xml(left['bytes']), notes)
            b = normalize_xml(parsed_xml(right['bytes']), notes)
            if canonical(a) == canonical(b):
                status = 'normalized'
            else:
                a, b, overrides = expected_configuration(unit, a, b, notes)
                if canonical(a) == canonical(b):
                    status = 'expected-configuration' if overrides else 'normalized'
                    if overrides:
                        record['overrides'] = overrides
                else:
                    status = 'unexpected'
    else:
        category = 'code'
        # Preserve CRLF, indentation, interior whitespace and extra trailing blank
        # lines. Only one optional final LF is a serializer-equivalent difference.
        status = 'exact' if left['bytes'] == right['bytes'] else (
            'normalized' if left['bytes'].removesuffix(b'\n') == right['bytes'].removesuffix(b'\n') else 'unexpected')
        if status == 'normalized':
            notes.add('optional-single-final-newline')
    record.update(category=category, status=status)
    if notes and status != 'unexpected':
        record['normalizations'] = sorted(notes)
    if status == 'unexpected':
        record['reason'] = 'Meaningful content differs; raw values and diffs are deliberately omitted.'
        if category != 'metadata':
            record['localSha256'] = digest(left['bytes'])
            record['snapshotSha256'] = digest(right['bytes'])
    return record


def compare(local, snapshot, manifest):
    if not local.is_dir() or not snapshot.is_dir():
        raise ComparisonError('Both source roots must be existing DX metadata directories.')
    members = manifest_members(manifest)
    units = inventory(members, local, snapshot)
    records, missing, failures = [], [], []
    consumed = {'local': set(), 'snapshot': set()}
    for path, unit in sorted(units.items()):
        try:
            left, right = read_unit(local, unit), read_unit(snapshot, unit)
            for side, found in (('local', left), ('snapshot', right)):
                if found:
                    consumed[side].update(found['aliases'])
                else:
                    missing.append({'path': path, 'type': unit['type'], 'missingFrom': side})
            if left is not None and right is not None:
                records.append(compare_unit(unit, left, right))
        except (ComparisonError, OSError, ValueError) as failure:
            failures.append({'path': path, 'type': unit['type'], 'reason': str(failure) if isinstance(failure, ComparisonError)
                             else 'Source comparison failed without exposing file contents.'})
    counts = Counter(record['status'] for record in records)
    categories = {category: dict(Counter(record['status'] for record in records if record['category'] == category))
                  for category in ('code', 'metadata', 'binary')}
    outside = {}
    for side, root in (('local', local), ('snapshot', snapshot)):
        files = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
        remaining = files - consumed[side]
        outside[side] = {'excludedToolingAndTests': len([p for p in remaining if excluded(Path(p))]),
                         'outOfManifest': sorted(p for p in remaining if not excluded(Path(p)))}
    unexpected = [record for record in records if record['status'] == 'unexpected']
    overrides = [record for record in records if record['status'] == 'expected-configuration']
    normalizations = [record for record in records if record.get('normalizations')]
    ok = not unexpected and not missing and not failures
    return {
        'schemaVersion': 1, 'generatedAt': datetime.now(timezone.utc).isoformat(),
        'result': 'PASS' if ok else 'FAIL',
        'scope': 'Explicit release manifest and children of selected CustomObjects/LWC bundles; supplied retrieved snapshot only.',
        'manifest': {'path': str(manifest.relative_to(ROOT)) if manifest.is_relative_to(ROOT) else manifest.name,
                     'sha256': digest(manifest.read_bytes()), 'membersByType': {kind: len(value) for kind, value in members.items()}},
        'localSource': str(local.relative_to(ROOT)) if local.is_relative_to(ROOT) else local.name,
        'snapshotSource': str(snapshot),
        'summary': {'scopedLogicalFiles': len(units), 'commonFilesCompared': len(records),
                    'exactMatches': counts['exact'], 'normalizedMatches': counts['normalized'],
                    'expectedConfigurationFiles': counts['expected-configuration'],
                    'unexpectedDifferences': len(unexpected), 'missingFiles': len(missing), 'comparisonFailures': len(failures),
                    'byCategory': categories},
        'expectedOrgConfiguration': overrides,
        'normalizations': normalizations,
        'unexpected': unexpected, 'missing': missing, 'comparisonFailures': failures,
        'excluded': outside,
        'privacy': 'No raw metadata/code diffs or running-user values are emitted. Principals are represented only by configured/unconfigured state.',
        'limitations': ['No org commands or network requests were run by this comparator.',
                        'A matching snapshot does not establish current org state, runtime correctness or unrelated org metadata parity.',
                        'XML sibling order is preserved except PermissionSet root set rows and CustomMetadata value rows; layouts and Flows retain order.',
                        'Only the two named feature booleans and five named subscriber running principals are expected configuration differences.',
                        'Inactive caseSensitive/trackHistory/trackTrending flags normalize only within CustomField roots; enabled flags and formula blank policies remain significant.'],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--local-source', type=Path, default=ROOT / 'force-app/main/default')
    parser.add_argument('--org-source', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'manifest/package.xml')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    local, snapshot, manifest = args.local_source.resolve(), args.org_source.resolve(), args.manifest.resolve()
    if output.is_relative_to(local) or output.is_relative_to(snapshot) or output in {manifest, Path(__file__).resolve()}:
        parser.error('The report cannot overwrite source, manifest or comparator files.')
    try:
        report = compare(local, snapshot, manifest)
    except (ComparisonError, OSError) as failure:
        report = {'schemaVersion': 1, 'result': 'FAIL', 'comparisonFailures': [str(failure) if isinstance(failure, ComparisonError)
                  else 'Source roots or manifest could not be read. No file contents are exposed.']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'result': report['result'], 'summary': report.get('summary'),
                      'unexpectedPaths': [item['path'] for item in report.get('unexpected', [])],
                      'report': str(args.output)}, indent=2))
    return 0 if report['result'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
