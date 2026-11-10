"""Snapshot parity must ignore inactive serializer flags without hiding real changes."""
import importlib.util
from pathlib import Path
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/'compare_org_snapshot.py'
SPEC=importlib.util.spec_from_file_location('aegis_snapshot_comparator',SCRIPT)
COMPARE=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPARE)
NS='http://soap.sforce.com/2006/04/metadata'


def field(extra='',label='Observed field',kind='Text',length='80'):
    return (f'<CustomField xmlns="{NS}"><fullName>Observed__c</fullName>'
            f'<label>{label}</label><length>{length}</length><type>{kind}</type>{extra}</CustomField>').encode()


def compare(left,right,kind='CustomField'):
    path='objects/Example__c/fields/Observed__c.field-meta.xml'
    unit={'path':path,'type':kind,'member':'Example__c.Observed__c'}
    return COMPARE.compare_unit(unit,{'path':path,'bytes':left},{'path':path,'bytes':right})


class OrgSnapshotComparisonTest(unittest.TestCase):
    def test_retrieved_inactive_field_flags_match_compact_source(self):
        for flag in ['caseSensitive','trackHistory','trackTrending']:
            for inactive in ['false','0']:
                with self.subTest(flag=flag,value=inactive):
                    result=compare(field(),field(f'<{flag}>{inactive}</{flag}>'))
                    self.assertEqual('normalized',result['status'])
                    self.assertTrue(result['normalizations'])

    def test_enabled_tracking_and_case_sensitive_uniqueness_remain_differences(self):
        for flag in ['caseSensitive','trackHistory','trackTrending']:
            with self.subTest(flag=flag):
                enabled=field(f'<{flag}>true</{flag}>')
                self.assertEqual('unexpected',compare(field(),enabled)['status'])
                self.assertEqual('unexpected',compare(field(f'<{flag}>false</{flag}>'),enabled)['status'])

    def test_other_field_changes_are_not_hidden_by_inactive_flags(self):
        defaults='<trackHistory>false</trackHistory><trackTrending>false</trackTrending>'
        for changes in [{'label':'Changed label'},{'kind':'Email'},{'length':'81'}]:
            with self.subTest(changes=changes):
                self.assertEqual('unexpected',compare(field(),field(defaults,**changes))['status'])

    def test_blank_formula_policy_is_never_discarded_as_a_boolean_default(self):
        blank=field('<formulaTreatBlanksAs>BlankAsBlank</formulaTreatBlanksAs>')
        zero=field('<formulaTreatBlanksAs>BlankAsZero</formulaTreatBlanksAs>')
        self.assertEqual('unexpected',compare(blank,zero)['status'])
        self.assertEqual('unexpected',compare(blank,field())['status'])

    def test_duplicate_boolean_settings_are_rejected(self):
        for flag in ['caseSensitive','trackHistory','trackTrending']:
            with self.subTest(flag=flag):
                duplicate=field(f'<{flag}>false</{flag}><{flag}>true</{flag}>')
                with self.assertRaises(COMPARE.ComparisonError):compare(field(),duplicate)

    def test_permission_and_object_configuration_changes_remain_visible(self):
        def permission(editable):
            return (f'<PermissionSet xmlns="{NS}"><label>Support</label><fieldPermissions>'
                    f'<editable>{editable}</editable><field>Example__c.Observed__c</field>'
                    '<readable>true</readable></fieldPermissions></PermissionSet>').encode()
        self.assertEqual('unexpected',compare(permission('false'),permission('true'),'PermissionSet')['status'])
        left=f'<CustomObject xmlns="{NS}"><label>Example</label></CustomObject>'.encode()
        right=f'<CustomObject xmlns="{NS}"><label>Example</label><trackHistory>false</trackHistory></CustomObject>'.encode()
        self.assertEqual('unexpected',compare(left,right,'CustomObject')['status'])

    def test_attribute_bearing_false_values_are_not_silently_removed(self):
        value=field('<trackHistory review="required">false</trackHistory>')
        self.assertEqual('unexpected',compare(field(),value)['status'])

    def test_empty_object_permission_rows_match_absence_without_hiding_grants(self):
        flags=['allowCreate','allowDelete','allowEdit','allowRead','modifyAllRecords','viewAllFields','viewAllRecords']
        def permission(enabled=None,extra=''):
            body=''.join(f'<{name}>{"true" if name==enabled else "false"}</{name}>' for name in flags)
            row=f'<objectPermissions>{body}<object>Diagnostic_Session_Requested__e</object>{extra}</objectPermissions>'
            return (f'<PermissionSet xmlns="{NS}"><label>End User</label>{row}</PermissionSet>').encode()
        empty=f'<PermissionSet xmlns="{NS}"><label>End User</label></PermissionSet>'.encode()
        self.assertEqual('normalized',compare(permission(),empty,'PermissionSet')['status'])
        for flag in flags:
            with self.subTest(enabled=flag):
                self.assertEqual('unexpected',compare(permission(flag),empty,'PermissionSet')['status'])
        self.assertEqual('unexpected',compare(permission(extra='<futurePermission>false</futurePermission>'),empty,'PermissionSet')['status'])


if __name__=='__main__':unittest.main()
