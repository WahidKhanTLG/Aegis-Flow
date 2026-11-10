#!/usr/bin/env python3
"""Validate prepared acceptance inputs, without executing commands or contacting an org."""

import argparse
from datetime import datetime
import json
from pathlib import Path, PurePosixPath
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PREPARATION = ROOT / 'release-preparation'
TASKS = {f'REL-{number:02}' for number in range(7, 15)} | {'REL-24'}


def present(value):
    return isinstance(value, str) and bool(value.strip())


def validate(catalog, profile, evidence, require_ready=False):
    errors = []
    if any(value.get('schemaVersion') != 1 for value in [catalog, profile, evidence]):
        errors.append('Preparation inputs must use the supported schema version.')
    references = set()
    cases = catalog.get('cases', [])
    ids = [case.get('id') for case in cases]
    if not cases or len(ids) != len(set(ids)):
        errors.append('Case identities must be present and unique.')
    if {case.get('task') for case in cases} != TASKS:
        errors.append('Case coverage must include REL-07 through REL-14 and REL-24.')
    for case in cases:
        if not re.fullmatch(r'ACC-(?:0[7-9]|1[0-4]|24)-[0-9]{2}', str(case.get('id', ''))):
            errors.append('A case identity has an invalid format.')
        elif case.get('task') != 'REL-' + case['id'][4:6]:
            errors.append('A case identity does not match its parent task.')
        if case.get('status') != 'Not run':
            errors.append('The portable case catalog must not contain executed results.')
        for field in ['requires', 'steps', 'expected', 'evidence', 'cleanup', 'existingCoverage']:
            values = case.get(field)
            if not isinstance(values, list) or not values or not all(present(v) for v in values):
                errors.append('A case is missing its preparation or evidence contract.')
        caps = case.get('caps')
        if not isinstance(caps, dict) or not caps or any(type(v) is not int or v < 0 or v > 2000 for v in caps.values()):
            errors.append('Fixture budgets must contain finite integers between zero and 2000.')
        for value in case.get('existingCoverage', []):
            relative = PurePosixPath(value)
            if relative.is_absolute() or '..' in relative.parts or '\\' in value or ':' in value:
                errors.append('Source coverage paths must stay inside the project.')
                continue
            path = ROOT / value
            if not path.resolve().is_relative_to(ROOT) or not path.is_file():
                errors.append('A referenced source or preparation file is missing or escapes the project.')
            references.add(value)
    evidence_cases = evidence.get('cases', [])
    if [case.get('id') for case in evidence_cases] != ids or any(case.get('status') != 'Not run' for case in evidence_cases):
        errors.append('The evidence template must match the catalog and contain no fabricated pass results.')
    for case in evidence_cases:
        if any(case.get(key) is not None for key in ['executedAtUtc', 'observedOutcome', 'reviewer', 'cleanupOutcome']):
            errors.append('Execution and review fields in the portable evidence template must remain unfilled.')
    if require_ready:
        target = profile.get('target', {})
        authority = profile.get('authority', {})
        scope = profile.get('scope', {})
        if not re.fullmatch(r'AEGIS-QA-[A-Za-z0-9_-]{1,55}', str(profile.get('runId', ''))):
            errors.append('Select a bounded synthetic run identity.')
        if not present(target.get('alias')) or not re.fullmatch(r'00D[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?', str(target.get('orgId', ''))):
            errors.append('Select the verified target alias and org identity.')
        if target.get('environmentType') not in {'sandbox', 'developer', 'scratch'}:
            errors.append('The execution profile must select a nonproduction environment.')
        try:
            verified = datetime.fromisoformat(str(target.get('verifiedAtUtc')).replace('Z', '+00:00'))
            if verified.tzinfo is None:
                raise ValueError('timezone required')
        except ValueError:
            errors.append('Record target verification time with a timezone.')
        if not re.fullmatch(r'[a-fA-F0-9]{64}', str(profile.get('releaseArtifactSha256', ''))):
            errors.append('Bind the exact reviewed artifact hash.')
        cli = profile.get('cli', {})
        if cli.get('qualificationState') != 'qualified' or not present(cli.get('qualificationEvidence')):
            errors.append('CLI-01 qualification remains required before credentialed execution.')
        owners = profile.get('owners', {})
        if not all(present(owners.get(key)) for key in ['release', 'salesforceAdmin', 'support', 'qa', 'security', 'customerProcess']):
            errors.append('Assign the operating and acceptance owners.')
        if not present(scope.get('customer')) or not present(scope.get('businessProcess')):
            errors.append('Select the customer or explicitly synthetic process scope.')
        selected = authority.get('approvedCaseIds', [])
        if not isinstance(selected, list) or not selected or len(selected) != len(set(selected)) or not set(selected) <= set(ids):
            errors.append('Select explicit known case identities without duplicates.')
            selected = []
        if not present(authority.get('approvalReference')) or authority.get('syntheticRecordWrites') is not True:
            errors.append('Record the selected action and synthetic-data authority.')
        if not present(profile.get('evidenceDirectory')):
            errors.append('Choose controlled evidence storage.')
        if 'ACC-08-03' in selected and scope.get('recoveryMode') != 'registered-recovery':
            errors.append('The recovery case requires a reviewed registered-recovery scope.')
        if 'ACC-09-02' in selected and not scope.get('mobileSurfaces'):
            errors.append('Select the supported mobile surface before its case.')
        if 'ACC-24-01' in selected and authority.get('metadataWrites') is not True:
            errors.append('The org rollback rehearsal requires separate metadata-write authority.')
        destinations = profile.get('destinations', {})
        if 'ACC-12-01' in selected and scope.get('concurrencyChannel') not in {'Email', 'Case'}:
            errors.append('Select the approved concurrency delivery channel.')
        email = 'ACC-10-01' in selected or ('ACC-12-01' in selected and scope.get('concurrencyChannel') == 'Email')
        case_delivery = 'ACC-10-02' in selected or ('ACC-12-01' in selected and scope.get('concurrencyChannel') == 'Case')
        if (email or case_delivery) and authority.get('externalDelivery') is not True:
            errors.append('Delivery and its downstream side effects need explicit approval.')
        if email and not present(destinations.get('emailRecipientApprovalReference')):
            errors.append('Record the approved email destination and sender decision.')
        if case_delivery and not present(destinations.get('caseOwnerOrQueueApprovalReference')):
            errors.append('Record the approved Case destination and automation decision.')
    return {'preparedCases': len(cases), 'taskCoverage': sorted(TASKS), 'sourceReferencesChecked': len(references),
            'readinessBindingsChecked': require_ready, 'orgActionsPerformed': False,
            'qualificationLimit': 'Structural checks do not verify an org, grant authority, resolve findings, or execute acceptance.',
            'errors': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, default=PREPARATION / 'acceptance-cases.json')
    parser.add_argument('--target-profile', type=Path, default=PREPARATION / 'target-profile.example.json')
    parser.add_argument('--require-ready', action='store_true')
    args = parser.parse_args()
    try:
        report = validate(json.loads(args.catalog.read_text()), json.loads(args.target_profile.read_text()),
                          json.loads((PREPARATION / 'acceptance-evidence.template.json').read_text()), args.require_ready)
        qualification = json.loads((PREPARATION / 'cli-qualification.json').read_text())
        report['cliCredentialedReleaseEligible'] = qualification.get('eligibleForCredentialedRelease') is True
        if args.require_ready and not report['cliCredentialedReleaseEligible']:
            report['errors'].append('The prepared CLI candidate still has an open release-security gate.')
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        report = {'orgActionsPerformed': False, 'errors': ['Preparation input could not be read or has an invalid structure.']}
    print(json.dumps(report, indent=2))
    return 1 if report['errors'] else 0


if __name__ == '__main__':
    sys.exit(main())
