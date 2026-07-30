/**
 * Automation health, reported from real failures rather than guesswork.
 *
 * The first version of this class inferred risk from Flow type, because
 * FlowDefinitionView cannot see fault connectors. That was a heuristic, and it overstated
 * the problem: it reported 44 "unprotected" Flows that may never have failed once.
 *
 * FlowInterview records every errored Flow run with the failing element and the full
 * message, so this now reports three concrete numbers per Flow:
 *
 *   failuresObserved - real errored interviews Salesforce recorded
 *   failuresCaptured - how many Aegis turned into an Error_Log__c
 *   captureGap       - the difference, which is the only number that needs action
 *
 * A Flow that never fails needs nothing, whatever its type. A Flow that fails and is not
 * captured is the actual problem.
 *
 * Caveat worth knowing: Salesforce purges errored interviews over time, so
 * failuresObserved is a recent window, not an all-time total.
 */
public with sharing class AEIR_FlowCoverageService {

    /** Flow types that fail without showing anyone an error. */
    private static final Set<String> SILENT_TYPES = new Set<String>{
        'AutoLaunchedFlow', 'Workflow', 'CustomEvent', 'InvocableProcess', 'Orchestrator'
    };

    public class FlowCoverage {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String processType;
        @AuraEnabled public String riskTier;
        @AuraEnabled public Integer failuresObserved;
        @AuraEnabled public Integer failuresCaptured;
        @AuraEnabled public Integer captureGap;
        @AuraEnabled public Datetime lastFailureAt;
        @AuraEnabled public String sampleError;
        @AuraEnabled public String failingElement;
        @AuraEnabled public String status;          // Healthy | Captured | Capture gap | Unreadable
        @AuraEnabled public String recommendation;
    }

    public class CoverageReport {
        @AuraEnabled public Integer totalActiveFlows;
        @AuraEnabled public Integer flowsWithFailures;
        @AuraEnabled public Integer totalFailuresObserved;
        @AuraEnabled public Integer totalFailuresCaptured;
        @AuraEnabled public Integer uncapturedFailures;
        @AuraEnabled public Integer silentRiskFlows;
        @AuraEnabled public Boolean interviewDataReadable;
        @AuraEnabled public String summary;
        @AuraEnabled public List<FlowCoverage> flows;
    }

    @AuraEnabled(cacheable=true)
    public static CoverageReport scan() {
        CoverageReport report = new CoverageReport();
        report.interviewDataReadable = true;

        // 1. Ground truth: what has actually failed.
        Map<String, FlowCoverage> byFlow = new Map<String, FlowCoverage>();
        try {
            for (FlowInterview interview : [
                SELECT InterviewLabel, CurrentElement, Error, CreatedDate
                FROM FlowInterview
                WHERE InterviewStatus = 'Error'
                ORDER BY CreatedDate DESC
                LIMIT 2000
            ]) {
                String flowName = flowNameFrom(interview.InterviewLabel);
                FlowCoverage row = byFlow.get(flowName);
                if (row == null) {
                    row = new FlowCoverage();
                    row.label = flowName;
                    row.apiName = flowName;
                    row.failuresObserved = 0;
                    row.failuresCaptured = 0;
                    // The list is ordered newest first, so the first hit is the latest.
                    row.lastFailureAt = interview.CreatedDate;
                    row.failingElement = interview.CurrentElement;
                    row.sampleError = AEIR_SecuritySanitizerService.safeTruncate(interview.Error, 500);
                    byFlow.put(flowName, row);
                }
                row.failuresObserved++;
            }
        } catch (Exception noAccess) {
            // Reading FlowInterview needs elevated access; degrade to a usable report.
            report.interviewDataReadable = false;
        }

        // 2. What Aegis actually captured, so the gap is visible.
        for (AggregateResult ar : [
            SELECT Source_Name__c name, COUNT(Id) total
            FROM Error_Log__c
            WHERE Source_Type__c = 'Flow' AND Source_Name__c != null
            GROUP BY Source_Name__c
            LIMIT 2000
        ]) {
            String raw = (String) ar.get('name');
            String flowName = raw.contains(' / ') ? raw.substringBefore(' / ').trim() : raw.trim();
            FlowCoverage row = byFlow.get(flowName);
            if (row == null) {
                row = new FlowCoverage();
                row.label = flowName;
                row.apiName = flowName;
                row.failuresObserved = 0;
                row.failuresCaptured = 0;
                byFlow.put(flowName, row);
            }
            row.failuresCaptured += (Integer) ar.get('total');
        }

        // 3. Overlay the active Flow inventory for type and risk context.
        Map<String, FlowDefinitionView> activeByLabel = new Map<String, FlowDefinitionView>();
        Integer activeCount = 0, silentRisk = 0;
        for (FlowDefinitionView view : [
            SELECT ApiName, Label, ProcessType, TriggerType
            FROM FlowDefinitionView WHERE IsActive = true LIMIT 500
        ]) {
            if (view.ApiName == 'Aegis_Error_Capture_Fault_Subflow') continue;
            activeCount++;
            if (SILENT_TYPES.contains(view.ProcessType) || String.isNotBlank(view.TriggerType)) silentRisk++;
            if (String.isNotBlank(view.Label)) activeByLabel.put(view.Label, view);
        }

        Integer observed = 0, captured = 0, gapFlows = 0;
        for (FlowCoverage row : byFlow.values()) {
            FlowDefinitionView view = activeByLabel.get(row.label);
            if (view != null) {
                row.apiName = view.ApiName;
                row.processType = view.ProcessType;
                row.riskTier = SILENT_TYPES.contains(view.ProcessType) || String.isNotBlank(view.TriggerType)
                    ? 'Silent failure' : 'User visible';
            } else {
                row.riskTier = 'Unknown';
            }
            row.captureGap = Math.max(0, row.failuresObserved - row.failuresCaptured);
            observed += row.failuresObserved;
            captured += row.failuresCaptured;

            if (row.failuresObserved == 0 && row.failuresCaptured > 0) {
                row.status = 'Captured';
                row.recommendation = 'Captured by Aegis Flow. The interview record has since been purged by Salesforce.';
            } else if (row.captureGap > 0) {
                gapFlows++;
                row.status = 'Capture gap';
                row.recommendation = row.captureGap + ' failure(s) are not in Aegis Flow. Confirm '
                    + 'AEIR_FlowInterviewMonitor is scheduled and that the running user can read FlowInterview.';
            } else {
                row.status = 'Captured';
                row.recommendation = 'All observed failures were captured. Add a fault path only if this Flow '
                    + 'needs an immediate, record-level diagnosis for the user.';
            }
        }

        List<FlowCoverage> flows = byFlow.values();
        flows.sort(new ByFailures());

        report.flows = flows;
        report.totalActiveFlows = activeCount;
        report.silentRiskFlows = silentRisk;
        report.flowsWithFailures = flows.size();
        report.totalFailuresObserved = observed;
        report.totalFailuresCaptured = captured;
        report.uncapturedFailures = Math.max(0, observed - captured);

        if (!report.interviewDataReadable) {
            report.summary = 'FlowInterview could not be read, so failures cannot be verified. '
                + 'Grant the running user access, or rely on fault-path instrumentation.';
        } else if (flows.isEmpty()) {
            report.summary = 'No Flow failures recorded. ' + activeCount + ' active Flow(s), '
                + silentRisk + ' of which would fail without showing anyone an error.';
        } else if (observed == 0) {
            // Salesforce purges errored interviews, so history can outlive the raw evidence.
            report.summary = 'No Flow failures in the current interview window. '
                + captured + ' previously captured failure(s) across ' + flows.size() + ' Flow(s) remain on record.';
        } else if (report.uncapturedFailures == 0) {
            report.summary = 'All ' + observed + ' recorded Flow failure(s) across '
                + flows.size() + ' Flow(s) were captured by Aegis Flow.';
        } else {
            report.summary = report.uncapturedFailures + ' of ' + observed + ' Flow failure(s) are not in '
                + 'Aegis Flow, across ' + gapFlows + ' Flow(s). Those failures are currently invisible.';
        }
        return report;
    }

    /** InterviewLabel is "<Flow Label> <timestamp>"; the timestamp must not split groups. */
    @TestVisible
    private static String flowNameFrom(String interviewLabel) {
        if (String.isBlank(interviewLabel)) return 'Unknown Flow';
        String stripped = Pattern.compile('\\s+\\d{1,2}/\\d{1,2}/\\d{4}.*$')
            .matcher(interviewLabel).replaceAll('').trim();
        return String.isBlank(stripped) ? 'Unknown Flow' : stripped;
    }

    /** Biggest capture gap first, then most failures: what an admin should look at first. */
    private class ByFailures implements Comparator<FlowCoverage> {
        public Integer compare(FlowCoverage a, FlowCoverage b) {
            if (a.captureGap != b.captureGap) return b.captureGap - a.captureGap;
            return b.failuresObserved - a.failuresObserved;
        }
    }
}