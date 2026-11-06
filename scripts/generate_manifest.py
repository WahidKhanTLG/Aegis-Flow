"""Build the explicit application manifest; development-only QA projects stay separate."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'force-app/main/default'
NS = 'http://soap.sforce.com/2006/04/metadata'
QA_FLOWS = {'Aegis_Test_Order_On_Closed_Won', 'Aegis_Test_Order_On_Closed_Won_With_Fault'}


def names(folder, suffix):
    return {p.name[:-len(suffix)] for p in (SOURCE / folder).glob('*' + suffix)}


def inventory():
    return {
        'ApexClass': names('classes', '.cls'),
        'ApexTrigger': names('triggers', '.trigger'),
        'CustomApplication': names('applications', '.app-meta.xml'),
        'CustomField': {f'{p.parent.parent.name}.{p.name[:-len(".field-meta.xml")]}'
                        for p in (SOURCE / 'objects').glob('*/fields/*.field-meta.xml')},
        'CustomMetadata': names('customMetadata', '.md-meta.xml'),
        'CustomObject': {p.parent.name for p in (SOURCE / 'objects').glob('*/*.object-meta.xml')},
        'CustomPermission': names('customPermissions', '.customPermission-meta.xml'),
        'CustomTab': names('tabs', '.tab-meta.xml'),
        'FlexiPage': names('flexipages', '.flexipage-meta.xml'),
        'Flow': names('flows', '.flow-meta.xml') - QA_FLOWS,
        'LightningComponentBundle': {p.name for p in (SOURCE / 'lwc').iterdir() if p.is_dir()},
        'Layout': names('layouts', '.layout-meta.xml'),
        'ListView': {f'{p.parent.parent.name}.{p.name[:-len(".listView-meta.xml")]}'
                     for p in (SOURCE / 'objects').glob('*/listViews/*.listView-meta.xml')},
        'PermissionSet': names('permissionsets', '.permissionset-meta.xml'),
        'PlatformEventSubscriberConfig': names('PlatformEventSubscriberConfigs', '.platformEventSubscriberConfig-meta.xml'),
        'QuickAction': names('quickActions', '.quickAction-meta.xml'),
        'StaticResource': names('staticresources', '.resource-meta.xml'),
    }


def main():
    import json
    items = inventory()
    output = ROOT / 'manifest/package.xml'
    if output.exists():
        previous = ET.parse(output)
        unknown = {p.findtext(f'{{{NS}}}name') for p in previous.findall(f'{{{NS}}}types')} - items.keys()
        if unknown:
            raise ValueError('Add manifest support before regenerating these types: ' + ', '.join(sorted(unknown)))
    ET.register_namespace('', NS)
    package = ET.Element(f'{{{NS}}}Package')
    for kind, members in sorted(items.items()):
        if not members:
            continue
        group = ET.SubElement(package, f'{{{NS}}}types')
        for member in sorted(members):
            ET.SubElement(group, f'{{{NS}}}members').text = member
        ET.SubElement(group, f'{{{NS}}}name').text = kind
    ET.SubElement(package, f'{{{NS}}}version').text = json.loads((ROOT / 'sfdx-project.json').read_text())['sourceApiVersion']
    ET.indent(package, space='    ')
    ET.ElementTree(package).write(output, encoding='UTF-8', xml_declaration=True)
    print('Explicit release manifest updated; QA flows/projects excluded.')


if __name__ == '__main__':
    main()
