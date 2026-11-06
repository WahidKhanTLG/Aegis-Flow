from pathlib import Path
import json
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
default = root / 'force-app/main/default'
errors = []
warnings = []
QA_FLOWS = {'Aegis_Test_Order_On_Closed_Won', 'Aegis_Test_Order_On_Closed_Won_With_Fault'}

# Only project metadata is audited. node_modules and tooling caches contain vendor
# template files that are intentionally not well-formed XML.
SKIP_DIRS = {'node_modules', '.sfdx', '.sf', '.git', 'coverage'}

def is_project_file(path):
    return not any(part in SKIP_DIRS for part in path.relative_to(root).parts)

for p in root.rglob('*.xml'):
    if not is_project_file(p):
        continue
    try:
        ET.parse(p)
    except Exception as exc:
        errors.append(f'XML parse failure: {p.relative_to(root)} :: {exc}')

for p in (default / 'classes').glob('*.cls'):
    if not p.with_name(p.name + '-meta.xml').exists():
        errors.append(f'Missing Apex class metadata: {p.relative_to(root)}')

for p in (default / 'triggers').glob('*.trigger'):
    if not p.with_name(p.name + '-meta.xml').exists():
        errors.append(f'Missing Apex trigger metadata: {p.relative_to(root)}')

for d in (default / 'lwc').iterdir():
    if d.is_dir() and not (d / f'{d.name}.js-meta.xml').exists():
        errors.append(f'Missing LWC metadata: {d.relative_to(root)}')

manifest = root / 'manifest/package.xml'
manifest_members = {}
if not manifest.exists():
    errors.append('Missing manifest/package.xml')
else:
    ns = {'m': 'http://soap.sforce.com/2006/04/metadata'}
    tree = ET.parse(manifest)
    for node in tree.findall('m:types', ns):
        name = node.findtext('m:name', namespaces=ns)
        manifest_members[name] = {m.text for m in node.findall('m:members', ns)}

    expected = {
        'ApexClass': {p.stem for p in (default/'classes').glob('*.cls')},
        'ApexTrigger': {p.stem for p in (default/'triggers').glob('*.trigger')},
        'LightningComponentBundle': {p.name for p in (default/'lwc').iterdir() if p.is_dir()},
        'PermissionSet': {p.name.replace('.permissionset-meta.xml','') for p in (default/'permissionsets').glob('*.permissionset-meta.xml')},
        'StaticResource': {p.name.replace('.resource-meta.xml','') for p in (default/'staticresources').glob('*.resource-meta.xml')},
        'CustomTab': {p.name.replace('.tab-meta.xml','') for p in (default/'tabs').glob('*.tab-meta.xml')},
        'CustomApplication': {p.name.replace('.app-meta.xml','') for p in (default/'applications').glob('*.app-meta.xml')},
        'CustomObject': {p.name for p in (default/'objects').iterdir() if p.is_dir() and (p / f'{p.name}.object-meta.xml').exists()},
        'CustomMetadata': {p.name.replace('.md-meta.xml','') for p in (default/'customMetadata').glob('*.md-meta.xml')},
        'CustomPermission': {p.name.replace('.customPermission-meta.xml','') for p in (default/'customPermissions').glob('*.customPermission-meta.xml')},
        'FlexiPage': {p.name.replace('.flexipage-meta.xml','') for p in (default/'flexipages').glob('*.flexipage-meta.xml')},
        'Flow': {p.name.replace('.flow-meta.xml','') for p in (default/'flows').glob('*.flow-meta.xml')} - QA_FLOWS,
        'PlatformEventSubscriberConfig': {p.name.replace('.platformEventSubscriberConfig-meta.xml','') for p in (default/'PlatformEventSubscriberConfigs').glob('*.platformEventSubscriberConfig-meta.xml')},
        'QuickAction': {p.name.replace('.quickAction-meta.xml','') for p in (default/'quickActions').glob('*.quickAction-meta.xml')},
        'Layout': {p.name.replace('.layout-meta.xml','') for p in (default/'layouts').glob('*.layout-meta.xml')},
    }
    for metadata_type, names in expected.items():
        missing = sorted(names - manifest_members.get(metadata_type, set()))
        if missing:
            errors.append(f'Manifest missing {metadata_type}: {", ".join(missing)}')

    fixtures_in_release = QA_FLOWS & manifest_members.get('Flow', set())
    if fixtures_in_release:
        errors.append('Release manifest contains QA failure fixtures: ' + ', '.join(sorted(fixtures_in_release)))
    ignored = set((root / '.forceignore').read_text().splitlines())
    for name in QA_FLOWS:
        if f'force-app/main/default/flows/{name}.flow-meta.xml' not in ignored:
            errors.append(f'QA fixture must be excluded from source deployments: {name}')

    for trigger in (default / 'triggers').glob('*.trigger'):
        config = default/'PlatformEventSubscriberConfigs'/f'{trigger.stem}.platformEventSubscriberConfig-meta.xml'
        if not config.exists():
            errors.append(f'Missing bounded event subscriber configuration: {trigger.stem}')
            continue
        definition = ET.parse(config)
        if definition.findtext('m:platformEventConsumer', namespaces=ns) != trigger.stem:
            errors.append(f'Event subscriber configuration points at the wrong consumer: {trigger.stem}')
        try:
            batch_size = int(definition.findtext('m:batchSize', namespaces=ns))
            if batch_size < 1 or batch_size > 200:
                errors.append(f'Event subscriber batch exceeds validated limits: {trigger.stem}')
        except (ValueError, TypeError):
            errors.append(f'Invalid event subscriber batch size: {trigger.stem}')

    consumer_roles = {'AEIR_End_User', 'AEIR_Developer_Viewer', 'AEIR_Support_Analyst', 'AEIR_Sample_Account_Remediation'}
    for name in consumer_roles:
        permissions = ET.parse(default/'permissionsets'/f'{name}.permissionset-meta.xml')
        for permission in permissions.findall('m:objectPermissions', ns):
            if permission.findtext('m:object', namespaces=ns) == 'Aegis_User_Alert__e' and permission.findtext('m:allowCreate', namespaces=ns) == 'true':
                errors.append(f'{name} must not publish trusted user alerts.')

sfdx = root / 'sfdx-project.json'
try:
    data = json.loads(sfdx.read_text())
    if not data.get('packageDirectories'):
        errors.append('sfdx-project.json has no packageDirectories')
except Exception as exc:
    errors.append(f'sfdx-project.json invalid: {exc}')

# Security baseline: evidence and action objects must not be public read/write.
private_objects = {
    'Error_Log__c','Diagnostic_Session__c','AI_Diagnosis__c','Developer_Escalation__c',
    'Remediation_Action__c','Error_Context__c','Error_Attachment__c','Error_Feedback__c',
    'Retry_Attempt__c','Delivery_Audit__c'
}
ns = {'m': 'http://soap.sforce.com/2006/04/metadata'}
event_commit_contracts = {
    'Error_Captured__e': 'PublishImmediately',
    'Agent_Diagnosis_Requested__e': 'PublishAfterCommit',
    'Aegis_User_Alert__e': 'PublishAfterCommit',
}
for name, expected in event_commit_contracts.items():
    definition = ET.parse(default/'objects'/name/f'{name}.object-meta.xml')
    actual = definition.findtext('m:publishBehavior', namespaces=ns)
    if actual != expected:
        errors.append(f'{name} publishBehavior must be {expected}, found {actual!r}')
for name in sorted(private_objects):
    p = default/'objects'/name/f'{name}.object-meta.xml'
    if not p.exists():
        errors.append(f'Missing security-critical object metadata: {name}')
        continue
    root_xml = ET.parse(p).getroot()
    sharing = root_xml.findtext('m:sharingModel', namespaces=ns)
    external = root_xml.findtext('m:externalSharingModel', namespaces=ns)
    if sharing != 'Private':
        errors.append(f'{name} sharingModel must be Private, found {sharing!r}')
    if external not in (None, 'Private'):
        errors.append(f'{name} externalSharingModel should be Private, found {external!r}')

# Reconciled package gates.
required_classes = {
    'AEIR_ReconciledFeaturesTest','AEIR_InboundDiagnosticRestService','AEIR_QueueableFinalizer',
    'AEIR_AsyncJobMonitorScheduler','AEIR_GetErrorContextAction','AEIR_FindRecentErrorsAction',
    'AEIR_GetRecordSnapshotAction','AEIR_UpdateMissingFieldAction','AEIR_ExecuteRetryHandlerAction'
}
actual_classes = {p.stem for p in (default/'classes').glob('*.cls')}
for name in sorted(required_classes - actual_classes):
    errors.append(f'Missing reconciled class: {name}')

# Confirm the package writes the accurate fallback status and never writes the legacy label.
code_text = '\n'.join(p.read_text(errors='ignore') for p in (default/'classes').glob('*.cls'))
if "Agent_Status__c = 'Deterministic Fallback'" not in code_text:
    errors.append('Deterministic fallback status assignment not found.')
if "Agent_Status__c = 'Mocked'" in code_text or "Agentforce_Status__c = 'Mocked'" in code_text:
    errors.append('Package code still writes the legacy Mocked status.')

print('Aegis Flow local audit')
print(f'Project root: {root}')
print(f'Files: {len([p for p in root.rglob("*") if p.is_file() and is_project_file(p)])}')
print(f'XML files checked: {len([p for p in root.rglob("*.xml") if is_project_file(p)])}')
print(f'Apex classes: {len(list((default / "classes").glob("*.cls")))}')
print(f'Apex triggers: {len(list((default / "triggers").glob("*.trigger")))}')
print(f'LWC bundles: {len([d for d in (default / "lwc").iterdir() if d.is_dir()])}')
print(f'Object/event/metadata directories: {len([d for d in (default / "objects").iterdir() if d.is_dir()])}')
print(f'Permission sets: {len(list((default / "permissionsets").glob("*.permissionset-meta.xml")))}')

if warnings:
    print('\nWARNINGS')
    for warning in warnings:
        print(f'- {warning}')
if errors:
    print('\nFAILURES')
    for err in errors:
        print(f'- {err}')
    sys.exit(1)

print('Result: PASS')
