# Rendered Salesforce UI acceptance

Target: `SyncBridge-Product` / `qbagentsync-dev-ed.develop.lightning.force.com`.
Status: all assigned rendered checks completed, with an explicit optional Flow stream limitation. Core live notices, saved-alert refresh and End User workflows passed.

Verified in actual Salesforce:

- Operations console, workspace and Aegis Admin utility render.
- Canonical operator notice and diagnostic show the same reference and a completed diagnosis.
- Contact quick action captures the existing Lead Source validation, retains the original error and unsaved draft, and displays a real capture reference. The corrected inner Cancel closes without saving.
- Case workspace saves a synthetic Description successfully.
- Custom-object help creates and analyzes a real session. The custom form saves Comments successfully, then restores its exact original QA marker.
- Registered correction preparation reads the approved smoke-test Account. Modal initial focus, Tab/Shift+Tab, Escape, Cancel and focus restoration pass. No correction was executed and the pre-existing Account was not changed.
- Read-only Setup health returns 10 PASS / 0 warnings / 0 failed after root corrected active scheduler-state counting. No onboarding data or probe was saved/run.
- Following specific user approval, all five Aegis subscribers were suspended and resumed from the earliest retained unprocessed message, then verified Running, batch200 and configured operator. AccountSyncBridgeCDC was untouched.

After specific user approval, the native **Administrators Can Log in as Any User** policy was temporarily enabled for QA-only Login As. In normal Sales, the End User saw only its own notice and canonical diagnosis. Separate Get Help on the QA-owned Contact created and analyzed a real session (`ERR-20261102-232906-BD04C827B855`). A fresh own notice was dismissed directly, then remained absent after a hard reload. Direct access to the existing foreign Error Log returned native Salesforce record-unavailable denial without diagnostic content. No escalation or report was sent.

The original own notice became Viewed when details were opened and was then omitted from the unread startup list; it did not expire. A separate fresh notice was used for the dismissal test.

Exiting Login As signed out the operator session too. Root immediately reopened the operator session, and the policy was restored to **OFF**, saved and verified after a reload at **2026-11-02 23:31:08 UTC** (approximately 290 seconds enabled). Original operator and correct org were verified. No password, profile or other security settings changed.

The original generic red monitor banner was corrected through a focused bundle deployment confirmed by root (`0AfgL00000cTYurSAG`). In the subsequent brief QA retest, the monitor displayed **Live alert subscription established**, a separate **Live Flow error capture is unavailable** warning, and **zero action-error elements**. One explicit Refresh alerts request completed successfully. The isolated own `AEIR-ENDUSER-2026-11-02_23:24:51.236-RECHECK` notice then arrived automatically without another refresh, and View details verified its exact reference. This demonstrates core live delivery and durable refresh; it does not establish the cause of the optional Flow stream failure or claim that optional stream is fixed.

The second approved policy window lasted approximately 114 seconds. The policy was restored to **OFF**, saved and hard-reload verified at **2026-11-02 23:40:35 UTC** under the original operator. The first click-save attempt did not persist and was caught by reload; immediate native Save via Enter succeeded and a fresh reload verified OFF. No further QA cycle is pending. Local validation for the deployed monitor change passed 105 LWC tests across 12 suites (53 monitor tests).

Screenshots were captured inline through CUA. The tool supplied no local screenshot export path, so no image file path is claimed. `observations.json` records the detailed observations, fixture references, warning and cleanup ownership. Some screenshots are historical evidence from before the subsequent fixes; the JSON distinguishes the corrected outcomes.

Root completed guarded cleanup of the prior acceptance fixtures; see [cleanup.json](../cleanup.json). Fresh approved End User follow-up fixtures now await root cleanup. The new Contact is `003gL00001Do7fpQAB`, follow-up marker is `AEIR-ENDUSER-2026-11-02_23:24:51.236`, and UI-created help correlation is `ERR-20261102-232906-BD04C827B855`. All exact diagnostic/notice references are in `observations.json`. QA Login As has ended and final policy OFF is verified, so cleanup can proceed. The same-marker `-RECHECK` correlation must also be included in final guarded cleanup.

The pre-existing smoke-test Account `001gL00001b2nbWQAQ` must not be deleted or changed. Prior custom Feedback Comments was restored to `AEIR-LIVE-1793649304960 Custom`. Prior UI-created session: `ERR-20261102-201634-309F67D039A2`; prior Contact capture: `ERR-20261102-200200-49F07F749138`.

Root final verification: metadata confirms Login As is OFF and security settings match the original snapshot. Fresh QA fixtures and diagnostics were removed with zero active residue; the QA user is inactive and its test role removed. See [cleanup](../cleanup.json).
