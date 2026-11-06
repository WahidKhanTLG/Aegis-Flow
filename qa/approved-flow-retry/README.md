# Approved Flow recovery acceptance fixture

This is a separate development-only Salesforce DX project. It is outside the product's
`force-app`, production manifest and production Apex-test dependencies. Do not deploy it
to production. The original QA order Flows are unchanged.

Deploy the product extension first. This QA project then supplies its own explicit custom
permission, small permission set, active synthetic Flow and QA-only retry registration.
An authorized operator also needs the normal Execute Retry capability, native retry-audit
CRUD/FLS and Error Feedback create/read/edit plus Comments field permissions. This QA
permission set grants the fixture entitlement only and does not broaden business access.

The only possible write is to `Comments__c` on an Error Feedback record owned by the
current user with the exact `AEIR-QA-RECOVERY:PENDING:<recoveryKey>` marker. The Flow changes
it to the corresponding `DONE` marker and reads back the result before reporting success.
Its idempotency branch recognizes an already stored matching result. Other records and
markers are rejected. There are no customer calculations, callouts, emails, immediate
events, screens, waits or async paths.

Root coordinates any org execution. From this directory the separate manifest is
`manifest/package.xml`; `acceptance.apex` exercises the **real Flow**, service-level
deduplication, a second successful idempotent attempt, and a rejected unmarked record.
It rolls back and verifies removal of its synthetic record and retry audits. On November 3 it was deployed separately to the authorized Aegis development org and the
real-Flow acceptance passed write verification, service deduplication, Flow idempotency and
unapproved-marker rejection. Synthetic rows/audits were rolled back. The Flow and retry
registration were then deactivated and the temporary QA permission assignment removed.
The checked-in fixture remains explicitly active for a future deliberate QA deployment.

Production unit tests use a private virtual runner to verify audited real database
mutations, failed-output rollback and native permission/record boundaries without
depending on this fixture. Those tests are distinct from this real-Flow proof.
