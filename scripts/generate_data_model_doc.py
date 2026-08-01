#!/usr/bin/env python3
"""
Regenerates docs/DATA_MODEL_AND_PROCESS_FLOW.md from the metadata in
force-app/main/default/objects.

The document is generated rather than hand-written so it cannot drift from the
schema. Run this after adding or changing any object or field:

    python3 scripts/generate_data_model_doc.py

The narrative sections (process flow, capture paths, relationships) live in this
script, so edit them here, not in the generated markdown.
"""
import os, re, glob, json, datetime, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, 'force-app/main/default/objects')
OUT = os.path.join(ROOT, 'docs/DATA_MODEL_AND_PROCESS_FLOW.md')

GROUPS = [
    ('Evidence and Diagnosis', 'Records the failure and what we concluded about it.',
     ['Error_Log__c', 'Error_Context__c', 'Incident__c', 'AI_Diagnosis__c', 'Error_Attachment__c']),
    ('User Assistance', 'Everything the affected user sees or contributes.',
     ['User_Notification__c', 'Diagnostic_Session__c', 'Error_Feedback__c']),
    ('Recovery', 'Corrective action, governed and audited.',
     ['Remediation_Action__c', 'Retry_Attempt__c']),
    ('Escalation and Delivery', 'Routing the evidence to a human, and proving it arrived.',
     ['Developer_Escalation__c', 'Delivery_Audit__c', 'Delivery_Attempt__c']),
    ('Platform Events',
     'Asynchronous handoffs. Error_Captured__e is PublishImmediately, so evidence survives a rollback.',
     ['Error_Captured__e', 'Agent_Diagnosis_Requested__e', 'Aegis_User_Alert__e',
      'Diagnostic_Session_Requested__e', 'Escalation_Requested__e']),
    ('Configuration (Custom Metadata)', 'Behaviour an admin changes without code.',
     ['Error_Rule__mdt', 'Severity_Rule__mdt', 'Notification_Policy__mdt', 'Escalation_Route__mdt',
      'SLA_Policy__mdt', 'Remediation_Action_Setting__mdt', 'Retry_Handler__mdt', 'Sensitive_Field__mdt',
      'Context_Field_Setting__mdt', 'Retention_Policy__mdt', 'Feature_Flag__mdt', 'Surface_Config__mdt']),
    ('Runtime Settings', 'Values captured during onboarding, editable at runtime.',
     ['Aegis_Org_Setting__c']),
]


def tag(source, name):
    m = re.search(rf'<{name}>(.*?)</{name}>', source, re.S)
    return m.group(1).strip() if m else None


def parse_objects():
    objs = {}
    if not os.path.isdir(BASE):
        sys.exit(f'Object directory not found: {BASE}')
    for name in sorted(os.listdir(BASE)):
        path = os.path.join(BASE, name, f'{name}.object-meta.xml')
        if not os.path.exists(path):
            continue
        s = open(path).read()
        if name.endswith('__e'):
            kind = 'Platform Event'
        elif name.endswith('__mdt'):
            kind = 'Custom Metadata Type'
        elif '<customSettingsType>' in s:
            kind = 'Custom Setting'
        elif not name.endswith('__c'):
            kind = 'Standard (extended)'
        else:
            kind = 'Custom Object'
        fields = []
        for fp in sorted(glob.glob(os.path.join(BASE, name, 'fields', '*.field-meta.xml'))):
            fs = open(fp).read()
            picks = re.findall(r'<fullName>([^<]+)</fullName>', tag(fs, 'valueSet') or '')
            fields.append({
                'name': tag(fs, 'fullName'), 'label': tag(fs, 'label'), 'type': tag(fs, 'type'),
                'len': tag(fs, 'length'), 'req': tag(fs, 'required') == 'true',
                'ext': tag(fs, 'externalId') == 'true', 'uniq': tag(fs, 'unique') == 'true',
                'ref': tag(fs, 'referenceTo'), 'desc': (tag(fs, 'description') or '').replace('\n', ' '),
                'picks': [p for p in picks if p][:12],
            })
        objs[name] = {'label': tag(s, 'label'), 'kind': kind, 'sharing': tag(s, 'sharingModel'),
                      'desc': (tag(s, 'description') or '').replace('\n', ' '),
                      'publish': tag(s, 'publishBehavior'), 'fields': fields}
    return objs


def field_row(f):
    t = f['type'] or '-'
    if f['len']:
        t += f"({f['len']})"
    flags = []
    if f['req']:
        flags.append('required')
    if f['ext']:
        flags.append('external id')
    if f['uniq']:
        flags.append('unique')
    if f['ref']:
        flags.append(f"→ {f['ref']}")
    notes = f['desc'] or ''
    if f['picks']:
        notes = (notes + ' ' if notes else '') + 'Values: ' + ', '.join(f['picks'])
    if flags:
        notes = (notes + ' ' if notes else '') + '**' + '; '.join(flags) + '**'
    return f"| `{f['name']}` | {f['label'] or '-'} | {t} | {notes.strip() or '-'} |"


def main():
    objs = parse_objects()
    counts = {k: sum(1 for o in objs.values() if o['kind'] == k) for k in
              ['Custom Object', 'Platform Event', 'Custom Metadata Type', 'Custom Setting']}
    out = ['# Aegis Flow — Data Model and Process Flow\n',
           f"**Generated:** {datetime.date.today().isoformat()} from `force-app/main/default/objects` (API 67.0)  ",
           f"**Objects:** {len(objs)} — {counts['Custom Object']} custom objects, "
           f"{counts['Platform Event']} platform events, {counts['Custom Metadata Type']} metadata types, "
           f"{counts['Custom Setting']} custom setting\n",
           '> Generated from metadata by `scripts/generate_data_model_doc.py`. '
           'Regenerate rather than editing by hand; narrative sections live in that script.\n',
           '---\n']
    out.append(NARRATIVE)
    out.append('## 3. Objects and fields\n')
    seen = set()
    for title, blurb, names in GROUPS:
        out.append(f'### {title}\n\n{blurb}\n')
        for n in names:
            o = objs.get(n)
            if not o:
                continue
            seen.add(n)
            meta = [o['kind']]
            if o['sharing'] and o['sharing'] != 'None':
                meta.append(f"sharing: **{o['sharing']}**")
            if o.get('publish'):
                meta.append(f"publish: **{o['publish']}**")
            out.append(f"#### `{n}` — {o['label']}\n")
            out.append(' · '.join(meta) + '  ')
            if o['desc']:
                out.append(f"\n{o['desc']}\n")
            out.append('\n| Field | Label | Type | Notes |\n|---|---|---|---|')
            out.extend(field_row(f) for f in o['fields'])
            out.append('')
    for n in [k for k in objs if k not in seen]:
        o = objs[n]
        out.append(f"#### `{n}` — {o['label']}\n")
        out.append('\n| Field | Label | Type | Notes |\n|---|---|---|---|')
        out.extend(field_row(f) for f in o['fields'])
        out.append('')
    open(OUT, 'w').write('\n'.join(out) + '\n')
    total = sum(len(o['fields']) for o in objs.values())
    print(f'Wrote {OUT}')
    print(f'  {len(objs)} objects, {total} fields')


NARRATIVE = """## 1. End-to-end process flow

```mermaid
flowchart TD
    subgraph SRC["1 · Failure happens"]
        F1["Flow fails<br/>(record-triggered, scheduled, autolaunched)"]
        F2["Apex throws"]
        F3["Batch Apex fails"]
        F4["Queueable / async job fails"]
        F5["Custom LWC errors"]
        F6["Integration posts to REST"]
    end

    subgraph CAP["2 · Capture"]
        FI[("FlowInterview<br/><i>Salesforce records it automatically</i>")]
        MON["AEIR_FlowInterviewMonitor<br/><i>scheduled every 15 min</i>"]
        GUARD["AEIR_Guard.capture()<br/><i>publishes, survives rollback</i>"]
        EVT(["Error_Captured__e<br/><b>PublishImmediately</b>"])
        SVC["AEIR_ErrorCaptureService"]
    end

    subgraph NORM["3 · Normalize"]
        MASK["AEIR_SecuritySanitizerService<br/><i>mask secrets</i>"]
        RULES["AEIR_ErrorNormalizationService<br/>+ Error_Rule__mdt"]
        INC["AEIR_IncidentAggregationService<br/><i>500 failures → 1 incident</i>"]
        LOG[("Error_Log__c")]
    end

    subgraph NOTIFY["4 · Notify"]
        POL{"AEIR_NotificationPolicyService<br/>severity · cooldown · hourly cap"}
        UN[("User_Notification__c")]
        ALERT(["Aegis_User_Alert__e<br/><i>user-safe payload only</i>"])
        LWC["aegisHeadlessMonitor<br/><i>utility bar</i>"]
    end

    subgraph ACT["5 · User acts"]
        HELP["Get Help →<br/>Diagnostic_Session__c"]
        FIX["Fix →<br/>Remediation_Action__c"]
        RETRY["Retry →<br/>Retry_Attempt__c"]
        ESC["Escalate →<br/>Developer_Escalation__c"]
    end

    F1 --> FI --> MON --> SVC
    F1 -.->|"optional fault path"| EVT
    F2 --> GUARD --> EVT
    F3 --> EVT
    F4 --> EVT
    F5 --> SVC
    F6 --> SVC
    EVT --> SVC
    SVC --> MASK --> RULES --> INC --> LOG
    LOG --> POL
    POL -->|allowed| UN --> ALERT --> LWC
    POL -.->|throttled| DROP["suppressed<br/><i>storm protection</i>"]
    LWC --> HELP & FIX & RETRY & ESC
    ESC --> DEL[("Delivery_Audit__c<br/>Email · Case")]
```

### Capture paths, and what each costs

| Source | Path | Instrumentation needed | Latency |
|---|---|---|---|
| Flow (any type) | `FlowInterview` → monitor | **None** | ≤ 15 min |
| Flow (critical) | Fault path → `Error_Captured__e` | Fault connector per Flow | Immediate |
| Apex | `AEIR_Guard.capture()` | One line in `catch` | Immediate |
| Batch Apex | `BatchApexErrorEvent` trigger | `Database.RaisesPlatformEvents` | Immediate |
| Queueable | `AEIR_QueueableFinalizer` | `System.attachFinalizer()` | Immediate |
| Async jobs | `AEIR_AsyncJobMonitorScheduler` | **None** | ≤ 1 hour |
| Custom LWC | `errorBoundaryWrapper` | Wrap component | Immediate |
| Integration | REST endpoint | Caller posts | Immediate |

> **Not capturable:** a validation rule blocking a direct save or a Lead Convert. The platform rejects those before any Apex or Flow can observe them.

---

## 2. Object relationships

```mermaid
erDiagram
    Error_Log__c ||--o{ Error_Context__c : "context rows"
    Error_Log__c ||--o{ AI_Diagnosis__c : "diagnosis"
    Error_Log__c ||--o{ User_Notification__c : "alerts"
    Error_Log__c ||--o{ Remediation_Action__c : "corrections"
    Error_Log__c ||--o{ Retry_Attempt__c : "retries"
    Error_Log__c ||--o{ Developer_Escalation__c : "escalations"
    Error_Log__c ||--o{ Error_Attachment__c : "file evidence"
    Error_Log__c ||--o{ Error_Feedback__c : "feedback"
    Incident__c ||--o{ Error_Log__c : "groups"
    Incident__c ||--o{ User_Notification__c : "groups"
    Diagnostic_Session__c ||--o{ AI_Diagnosis__c : "diagnosis"
    Diagnostic_Session__c ||--o{ Remediation_Action__c : "proposed"
    Diagnostic_Session__c ||--o{ Error_Feedback__c : "feedback"
    Developer_Escalation__c ||--o{ Delivery_Audit__c : "delivery"
    Developer_Escalation__c ||--o{ Delivery_Attempt__c : "attempts"
    User ||--o{ Error_Log__c : "affected"
    User ||--o{ User_Notification__c : "target"
```

Every record also carries `Correlation_Id__c`, which ties one failure together across all objects and is the reference number shown to the user.

---

"""


if __name__ == '__main__':
    main()
