public without sharing class AEIR_UserNotificationService {
    public class AlertDTO {
        @AuraEnabled public Id notificationId;
        @AuraEnabled public Id errorLogId;
        @AuraEnabled public String correlationId;
        @AuraEnabled public String headline;
        @AuraEnabled public String shortMessage;
        @AuraEnabled public String severity;
        @AuraEnabled public String notificationType;
        @AuraEnabled public String actionAvailable;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime expiresAt;
        @AuraEnabled public Datetime createdDate;
    }
    public class DetailDTO {
        @AuraEnabled public AlertDTO alert;
        @AuraEnabled public ErrorLogDTO errorLog;
        @AuraEnabled public AI_Diagnosis__c diagnosis;
        @AuraEnabled public Boolean canEscalate;
    }
    /**
     * Explicit user-safe projection. Never return Error_Log__c directly from an Aura
     * method: doing so makes newly added technical fields public by accident.
     */
    public class ErrorLogDTO {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String correlationId;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String sourceName;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String affectedRecordId;
        @AuraEnabled public String actionName;
        @AuraEnabled public String pageUrl;
        @AuraEnabled public String category;
        @AuraEnabled public String severity;
        @AuraEnabled public String status;
        @AuraEnabled public String normalizedMessage;
        @AuraEnabled public Boolean retryEligible;
        @AuraEnabled public Datetime createdDate;
    }

    public static void notifyForErrorLogs(List<Error_Log__c> logs) {
        if (logs == null || logs.isEmpty()) return;
        Datetime nowValue = Datetime.now();
        List<User_Notification__c> toInsert = new List<User_Notification__c>();
        Set<String> dedupeKeys = new Set<String>();
        for (Error_Log__c log : logs) {
            if (log == null || log.User__c == null || String.isBlank(log.Correlation_Id__c)) continue;
            String dedupe = log.Correlation_Id__c + ':' + String.valueOf(log.User__c);
            dedupeKeys.add(dedupe);
        }
        if (dedupeKeys.isEmpty()) return;
        Set<String> existingKeys = new Set<String>();
        for (User_Notification__c existing : [SELECT Dedupe_Key__c FROM User_Notification__c WHERE Dedupe_Key__c IN :dedupeKeys]) {
            existingKeys.add(existing.Dedupe_Key__c);
        }
        // Severity, cooldown, and hourly-cap gating (spec 9.1). Evaluated for the whole
        // batch at once so a storm cannot slip through one row at a time.
        Map<Id, AEIR_NotificationPolicyService.Decision> policyDecisions =
            AEIR_NotificationPolicyService.evaluate(logs);
        for (Error_Log__c log : logs) {
            if (log == null || log.User__c == null || String.isBlank(log.Correlation_Id__c)) continue;
            String dedupe = log.Correlation_Id__c + ':' + String.valueOf(log.User__c);
            if (existingKeys.contains(dedupe)) continue;
            AEIR_NotificationPolicyService.Decision decision = policyDecisions.get(log.Id);
            if (decision != null && decision.allowed != true) continue;
            String severity = String.isBlank(log.Severity__c) ? 'Medium' : log.Severity__c;
            String message = String.isBlank(log.Normalized_Message__c) ? 'A Salesforce process encountered an issue. Aegis Flow preserved the diagnostic evidence.' : log.Normalized_Message__c;
            User_Notification__c item = new User_Notification__c();
            item.Correlation_Id__c = log.Correlation_Id__c;
            item.Target_User__c = log.User__c;
            item.Error_Log__c = log.Id;
            item.Notification_Type__c = 'Detected';
            item.Severity__c = severity;
            item.Headline__c = 'I have identified the issue.';
            item.Short_Message__c = AEIR_SecuritySanitizerService.safeTruncate(message, 4000);
            item.Action_Available__c = log.Retry_Eligible__c == true ? 'RETRY' : 'VIEW';
            item.Status__c = 'New';
            item.Expires_At__c = nowValue.addHours(24);
            item.Dedupe_Key__c = dedupe;
            item.OwnerId = log.User__c;
            toInsert.add(item);
        }
        if (toInsert.isEmpty()) return;
        Database.SaveResult[] insertResults = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        List<Aegis_User_Alert__e> events = new List<Aegis_User_Alert__e>();
        List<Delivery_Attempt__c> attempts = new List<Delivery_Attempt__c>();
        for (Integer i = 0; i < insertResults.size(); i++) {
            User_Notification__c item = toInsert[i];
            Database.SaveResult sr = insertResults[i];
            if (!sr.isSuccess()) {
                attempts.add(deliveryAttempt(item.Correlation_Id__c, 'Platform Event', 'Failed', firstError(sr.getErrors()), item.Dedupe_Key__c));
                continue;
            }
            item.Id = sr.getId();
            events.add(new Aegis_User_Alert__e(
                Correlation_Id__c = item.Correlation_Id__c,
                Target_User_Id__c = String.valueOf(item.Target_User__c),
                Error_Log_Id__c = String.valueOf(item.Error_Log__c),
                Notification_Type__c = item.Notification_Type__c,
                Severity__c = item.Severity__c,
                Headline__c = item.Headline__c,
                Short_Message__c = item.Short_Message__c,
                Action_Available__c = item.Action_Available__c,
                Occurred_At__c = nowValue,
                Expires_At__c = item.Expires_At__c
            ));
        }
        if (!events.isEmpty()) {
            Database.SaveResult[] eventResults = EventBus.publish(events);
            for (Integer i = 0; i < eventResults.size(); i++) {
                Database.SaveResult sr = eventResults[i];
                Aegis_User_Alert__e evt = events[i];
                attempts.add(deliveryAttempt(evt.Correlation_Id__c, 'Platform Event', sr.isSuccess() ? 'Delivered' : 'Failed', sr.isSuccess() ? 'Aegis user alert event published.' : firstError(sr.getErrors()), evt.Correlation_Id__c + ':alert'));
            }
        }
        if (!attempts.isEmpty()) Database.insert(attempts, false, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Second half of the async round trip (spec 6.5). Capture publishes a "Detected"
     * alert so the utility shows a spinner; this replaces it with the outcome once
     * diagnosis finishes. Without it the spinner never resolves.
     */
    public static void notifyDiagnosisComplete(Error_Log__c log, String fixability, String summary) {
        notifyDiagnosisCompleteAll(
            new List<Error_Log__c>{ log },
            new Map<Id, String>{ log == null ? null : log.Id => fixability },
            new Map<Id, String>{ log == null ? null : log.Id => summary });
    }

    /**
     * Batched form of the above. The single-record version cost one query, one update and one
     * audit insert per log, so an error storm diagnosed in a platform event batch exhausted
     * limits before the users were told anything - the spinner in the utility bar then never
     * resolved, which is the failure the notification exists to prevent.
     *
     * One query for existing notifications, one update, one publish for the whole set, one
     * audit insert.
     */
    public static void notifyDiagnosisCompleteAll(List<Error_Log__c> logs,
                                                  Map<Id, String> fixabilityByLog,
                                                  Map<Id, String> summaryByLog) {
        if (logs == null || logs.isEmpty()) return;
        if (!AEIR_FeatureFlagService.isEnabled(AEIR_FeatureFlagService.USER_NOTIFICATIONS)) return;

        List<Error_Log__c> notifiable = new List<Error_Log__c>();
        Set<String> correlationIds = new Set<String>();
        Set<Id> userIds = new Set<Id>();
        for (Error_Log__c log : logs) {
            if (log == null || log.User__c == null || String.isBlank(log.Correlation_Id__c)) continue;
            notifiable.add(log);
            correlationIds.add(log.Correlation_Id__c);
            userIds.add(log.User__c);
        }
        if (notifiable.isEmpty()) return;

        // Keyed on correlation id + user, the same pair the single-record query filtered on.
        Map<String, User_Notification__c> existingByKey = new Map<String, User_Notification__c>();
        for (User_Notification__c row : [
            SELECT Id, Correlation_Id__c, Target_User__c, Notification_Type__c, Headline__c,
                   Short_Message__c, Action_Available__c, Status__c
            FROM User_Notification__c
            WHERE Correlation_Id__c IN :correlationIds AND Target_User__c IN :userIds
            ORDER BY CreatedDate ASC
        ]) {
            // ASC so the last write wins, matching the single-record "most recent" query.
            existingByKey.put(row.Correlation_Id__c + '|' + row.Target_User__c, row);
        }

        List<User_Notification__c> toUpdate = new List<User_Notification__c>();
        List<Aegis_User_Alert__e> alerts = new List<Aegis_User_Alert__e>();
        List<Error_Log__c> alerted = new List<Error_Log__c>();

        for (Error_Log__c log : notifiable) {
            String fixability = fixabilityByLog == null ? null : fixabilityByLog.get(log.Id);
            String rawSummary = summaryByLog == null ? null : summaryByLog.get(log.Id);
            String action = actionForFixability(fixability);
            String headline = headlineForFixability(fixability);
            String message = AEIR_SecuritySanitizerService.safeTruncate(
                String.isBlank(rawSummary) ? 'Aegis Flow finished analyzing this issue.' : rawSummary, 4000);

            User_Notification__c existing = existingByKey.get(log.Correlation_Id__c + '|' + log.User__c);
            if (existing != null) {
                // A user who dismissed the alert is not re-notified.
                if (existing.Status__c == 'Dismissed') continue;
                existing.Notification_Type__c = 'Diagnosed';
                existing.Headline__c = headline;
                existing.Short_Message__c = message;
                existing.Action_Available__c = action;
                toUpdate.add(existing);
            }

            alerts.add(new Aegis_User_Alert__e(
                Correlation_Id__c = log.Correlation_Id__c,
                Target_User_Id__c = String.valueOf(log.User__c),
                Error_Log_Id__c = String.valueOf(log.Id),
                Notification_Type__c = 'Diagnosed',
                Severity__c = String.isBlank(log.Severity__c) ? 'Medium' : log.Severity__c,
                Headline__c = headline,
                Short_Message__c = message,
                Action_Available__c = action,
                Occurred_At__c = Datetime.now(),
                Expires_At__c = Datetime.now().addHours(24)
            ));
            alerted.add(log);
        }

        if (!toUpdate.isEmpty()) Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        if (alerts.isEmpty()) return;

        List<Database.SaveResult> published = EventBus.publish(alerts);
        List<Delivery_Attempt__c> attempts = new List<Delivery_Attempt__c>();
        for (Integer i = 0; i < alerted.size() && i < published.size(); i++) {
            Database.SaveResult sr = published[i];
            attempts.add(deliveryAttempt(alerted[i].Correlation_Id__c, 'Platform Event',
                sr.isSuccess() ? 'Delivered' : 'Failed',
                sr.isSuccess() ? 'Aegis diagnosis alert published.' : firstError(sr.getErrors()),
                alerted[i].Correlation_Id__c + ':diagnosed'));
        }
        if (!attempts.isEmpty()) Database.insert(attempts, false, AccessLevel.SYSTEM_MODE);
    }


    /** Spec 6.5 wording, chosen by fixability. */
    private static String headlineForFixability(String fixability) {
        if (fixability == 'USER_FIXABLE') return 'I have identified the issue.';
        if (fixability == 'RETRYABLE') return 'A temporary issue interrupted the process. A safe retry is available.';
        if (fixability == 'DEVELOPER_ONLY' || fixability == 'ADMIN_FIXABLE') {
            return 'I found the issue, but it requires technical assistance. A diagnostic package is ready.';
        }
        return 'I have finished reviewing this issue.';
    }
    private static String actionForFixability(String fixability) {
        if (fixability == 'USER_FIXABLE') return 'FIX';
        if (fixability == 'RETRYABLE') return 'RETRY';
        if (fixability == 'DEVELOPER_ONLY' || fixability == 'ADMIN_FIXABLE') return 'ESCALATE';
        return 'HELP';
    }

    @AuraEnabled(cacheable=true)
    public static List<AlertDTO> getOpenAlerts() {
        Id uid = UserInfo.getUserId();
        Datetime nowValue = Datetime.now();
        List<AlertDTO> output = new List<AlertDTO>();
        for (User_Notification__c item : [SELECT Id, Error_Log__c, Correlation_Id__c, Headline__c, Short_Message__c, Severity__c,
                                                 Notification_Type__c, Action_Available__c, Status__c, Expires_At__c, CreatedDate
                                          FROM User_Notification__c
                                          WHERE Target_User__c = :uid AND Status__c = 'New' AND Expires_At__c >= :nowValue
                                          ORDER BY CreatedDate DESC LIMIT 20]) {
            output.add(toDto(item));
        }
        return output;
    }

    /**
     * Details for one alert.
     *
     * Throttling controls interruption, not access. A capture whose notification was
     * suppressed by cooldown or the hourly cap still has an Error_Log__c, and the utility
     * bar may legitimately be showing it from the real-time Flow event stream. So when no
     * notification exists this falls back to the error log, and only refuses when the
     * record genuinely does not belong to the caller.
     */
    @AuraEnabled
    public static DetailDTO getAlertDetails(String correlationId) {
        if (String.isBlank(correlationId)) throw new AuraHandledException('Correlation id is required.');
        Id uid = UserInfo.getUserId();

        List<User_Notification__c> notifications = [SELECT Id, Error_Log__c, Correlation_Id__c, Headline__c, Short_Message__c, Severity__c,
                                                           Notification_Type__c, Action_Available__c, Status__c, Expires_At__c, CreatedDate
                                                    FROM User_Notification__c
                                                    WHERE Correlation_Id__c = :correlationId AND Target_User__c = :uid
                                                    ORDER BY CreatedDate DESC LIMIT 1];

        Id errorLogId;
        DetailDTO detail = new DetailDTO();
        detail.canEscalate = false;

        if (!notifications.isEmpty()) {
            User_Notification__c notice = notifications[0];
            if (notice.Status__c == 'New') {
                notice.Status__c = 'Viewed';
                notice.Viewed_At__c = Datetime.now();
                Database.update(new List<User_Notification__c>{ notice }, true, AccessLevel.SYSTEM_MODE);
            }
            detail.alert = toDto(notice);
            errorLogId = notice.Error_Log__c;
        } else {
            // No notification: either it was policy-suppressed, or the alert came straight
            // from the real-time Flow error stream before any notification was created.
            List<Error_Log__c> logs = [SELECT Id, User__c, Severity__c, Normalized_Message__c
                                       FROM Error_Log__c
                                       WHERE Correlation_Id__c = :correlationId
                                       ORDER BY CreatedDate DESC LIMIT 1];
            if (logs.isEmpty()) {
                throw new AuraHandledException('That Aegis Flow diagnostic no longer exists. It may have been purged by the retention policy.');
            }
            if (logs[0].User__c != uid) {
                throw new AuraHandledException('You are not authorized to view this Aegis Flow diagnostic.');
            }
            errorLogId = logs[0].Id;

            // Synthesize an alert view so the panel renders consistently.
            AlertDTO synthetic = new AlertDTO();
            synthetic.correlationId = correlationId;
            synthetic.errorLogId = errorLogId;
            synthetic.severity = String.isBlank(logs[0].Severity__c) ? 'Medium' : logs[0].Severity__c;
            synthetic.headline = 'I have identified the issue.';
            synthetic.shortMessage = logs[0].Normalized_Message__c;
            synthetic.notificationType = 'Detected';
            synthetic.actionAvailable = 'VIEW';
            synthetic.status = 'Viewed';
            detail.alert = synthetic;
        }

        if (errorLogId != null) {
            // A list, not a bare assignment. `SELECT ... LIMIT 1` into an sObject throws
            // QueryException the moment the row is invisible under sharing or was deleted
            // between this query and the one that produced the id - and that exception would
            // reach the user as a raw platform message instead of the panel.
            List<Error_Log__c> logs = [SELECT Id, Correlation_Id__c, Source_Type__c, Source_Name__c, Object_API_Name__c, Record_Id__c,
                                              Error_Category__c, Severity__c, Status__c, Normalized_Message__c,
                                              Page_URL__c, Action_Name__c, Retry_Eligible__c, CreatedDate
                                       FROM Error_Log__c WHERE Id = :errorLogId LIMIT 1];
            if (!logs.isEmpty()) {
                detail.errorLog = toErrorLogDto(logs[0]);
                List<AI_Diagnosis__c> diagnoses = [SELECT Id, Summary__c, Root_Cause__c, Fixability__c, Confidence__c, Recommended_Action__c,
                                                          Escalation_Required__c, Needs_User_Input__c, Safe_Remediation_Action_Key__c, Agent_Status__c
                                                   FROM AI_Diagnosis__c WHERE Error_Log__c = :errorLogId ORDER BY CreatedDate DESC LIMIT 1];
                detail.diagnosis = diagnoses.isEmpty() ? null : diagnoses[0];
                // Only true when there is an Error Log to build a diagnostic package from.
                detail.canEscalate = true;
            }
        }
        return detail;
    }

    @AuraEnabled
    public static void dismiss(String correlationId) {
        updateStatus(correlationId, 'Dismissed');
    }
    @AuraEnabled
    public static void markResolved(String correlationId) {
        updateStatus(correlationId, 'Resolved');
    }
    private static void updateStatus(String correlationId, String status) {
        Id uid = UserInfo.getUserId();
        List<User_Notification__c> rows = [SELECT Id, Status__c, Dismissed_At__c FROM User_Notification__c WHERE Correlation_Id__c = :correlationId AND Target_User__c = :uid LIMIT 1];
        if (rows.isEmpty()) throw new AuraHandledException('Notification not found or not authorized.');
        rows[0].Status__c = status;
        if (status == 'Dismissed') rows[0].Dismissed_At__c = Datetime.now();
        Database.update(rows, true, AccessLevel.SYSTEM_MODE);
    }

    private static AlertDTO toDto(User_Notification__c item) {
        AlertDTO dto = new AlertDTO();
        dto.notificationId = item.Id;
        dto.errorLogId = item.Error_Log__c;
        dto.correlationId = item.Correlation_Id__c;
        dto.headline = item.Headline__c;
        dto.shortMessage = item.Short_Message__c;
        dto.severity = item.Severity__c;
        dto.notificationType = item.Notification_Type__c;
        dto.actionAvailable = item.Action_Available__c;
        dto.status = item.Status__c;
        dto.expiresAt = item.Expires_At__c;
        dto.createdDate = item.CreatedDate;
        return dto;
    }
    private static ErrorLogDTO toErrorLogDto(Error_Log__c log) {
        ErrorLogDTO dto = new ErrorLogDTO();
        dto.recordId = log.Id;
        dto.correlationId = log.Correlation_Id__c;
        dto.sourceType = log.Source_Type__c;
        dto.sourceName = log.Source_Name__c;
        dto.objectApiName = log.Object_API_Name__c;
        dto.affectedRecordId = log.Record_Id__c;
        dto.actionName = log.Action_Name__c;
        dto.pageUrl = log.Page_URL__c;
        dto.category = log.Error_Category__c;
        dto.severity = log.Severity__c;
        dto.status = log.Status__c;
        dto.normalizedMessage = log.Normalized_Message__c;
        dto.retryEligible = log.Retry_Eligible__c;
        dto.createdDate = log.CreatedDate;
        return dto;
    }
    private static Delivery_Attempt__c deliveryAttempt(String correlationId, String channel, String status, String response, String key) {
        return new Delivery_Attempt__c(Correlation_Id__c = correlationId, Channel__c = channel, Status__c = status, Response_Body__c = AEIR_SecuritySanitizerService.safeTruncate(response, 32768), Attempt_Count__c = 1, Idempotency_Key__c = key);
    }
    private static String firstError(Database.Error[] errors) {
        return errors == null || errors.isEmpty() ? 'Unknown platform error.' : errors[0].getMessage();
    }
}
