@IsTest
private class AEIR_NotificationBoundaryTest {
    @TestSetup
    static void createRecipients() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> recipients = new List<User>();
        String uniquePart = UserInfo.getOrganizationId() + '.' + Datetime.now().getTime();
        for (Integer i = 0; i < 2; i++) {
            recipients.add(new User(
                LastName = 'AegisNotificationBoundary', Alias = 'aegbn' + i,
                Email = 'aegis.boundary.' + i + '@example.com',
                Username = 'aegis.boundary.' + uniquePart + '.' + i + '@example.com',
                ProfileId = standard.Id, TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            ));
        }
        insert recipients;
        PermissionSet consumer = [SELECT Id FROM PermissionSet WHERE Name = 'AEIR_End_User' LIMIT 1];
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (User recipient : recipients) {
            assignments.add(new PermissionSetAssignment(AssigneeId = recipient.Id, PermissionSetId = consumer.Id));
        }
        insert assignments;
    }

    private static User recipient(Integer index) {
        String alias = 'aegbn' + index;
        return [SELECT Id FROM User WHERE LastName = 'AegisNotificationBoundary' AND Alias = :alias LIMIT 1];
    }

    private static User_Notification__c notice(Id uid, String correlation, String status, Datetime expiresAt) {
        return new User_Notification__c(
            OwnerId = uid, Target_User__c = uid, Correlation_Id__c = correlation,
            Dedupe_Key__c = correlation + ':' + uid, Status__c = status,
            Expires_At__c = expiresAt, Notification_Type__c = 'Detected',
            Headline__c = 'Canonical server headline', Short_Message__c = 'Authorized diagnostic summary',
            Severity__c = 'Medium', Action_Available__c = 'VIEW'
        );
    }

    @IsTest
    static void resolvesOwnedNoticeWithoutMarkingItViewed() {
        User owner = recipient(0);
        User_Notification__c item = notice(owner.Id, 'BOUNDARY-OWN', 'New', Datetime.now().addHours(1));
        insert item;

        System.runAs(owner) {
            Test.startTest();
            Integer beforeDml = Limits.getDmlStatements();
            AEIR_UserNotificationService.AlertDTO resolved =
                AEIR_AegisHeadlessMonitorController.resolveAlert(item.Correlation_Id__c);
            System.assertEquals(beforeDml, Limits.getDmlStatements(), 'A wake-up lookup must not mutate unread state.');
            System.assertNotEquals(null, resolved);
            System.assertEquals(item.Id, resolved.notificationId);
            System.assertEquals('Canonical server headline', resolved.headline);
            System.assertEquals('Authorized diagnostic summary', resolved.shortMessage);
            System.assertEquals('New', resolved.status);
            Test.stopTest();
        }
        User_Notification__c stored = [SELECT Status__c, Viewed_At__c FROM User_Notification__c WHERE Id = :item.Id];
        System.assertEquals('New', stored.Status__c);
        System.assertEquals(null, stored.Viewed_At__c);
    }

    @IsTest
    static void rejectsOtherRecipientsUnknownHintsAndSuppressedLogs() {
        User owner = recipient(0);
        User other = recipient(1);
        User_Notification__c privateNotice = notice(other.Id, 'BOUNDARY-OTHER', 'New', Datetime.now().addHours(1));
        insert privateNotice;
        insert new Error_Log__c(
            Correlation_Id__c = 'BOUNDARY-SUPPRESSED', User__c = owner.Id, OwnerId = owner.Id,
            Source_Type__c = 'API', Status__c = 'New', Severity__c = 'Medium'
        );

        System.runAs(owner) {
            Test.startTest();
            System.assertEquals(null, AEIR_AegisHeadlessMonitorController.resolveAlert('BOUNDARY-OTHER'),
                'Possessing another user\'s correlation must not reveal their alert.');
            System.assertEquals(null, AEIR_AegisHeadlessMonitorController.resolveAlert('BOUNDARY-SUPPRESSED'),
                'A wakeUpHint cannot bypass notification policy by falling back to an error log.');
            System.assertEquals(null, AEIR_AegisHeadlessMonitorController.resolveAlert('FORGED-CORRELATION'));
            System.assertEquals(null, AEIR_AegisHeadlessMonitorController.resolveAlert(null));
            System.assertEquals(null, AEIR_AegisHeadlessMonitorController.resolveAlert('  '));
            Test.stopTest();
        }
    }

    @IsTest
    static void enforcesExpiryAndLifecycleWithoutResurrectingNotices() {
        User owner = recipient(0);
        Datetime future = Datetime.now().addHours(1);
        insert new List<User_Notification__c>{
            notice(owner.Id, 'BOUNDARY-VIEWED', 'Viewed', future),
            notice(owner.Id, 'BOUNDARY-DISMISSED', 'Dismissed', future),
            notice(owner.Id, 'BOUNDARY-RESOLVED', 'Resolved', future),
            notice(owner.Id, 'BOUNDARY-EXPIRED-STATUS', 'Expired', future),
            notice(owner.Id, 'BOUNDARY-EXPIRED-TIME', 'New', Datetime.now().addSeconds(-1)),
            notice(owner.Id, 'BOUNDARY-MISSING-EXPIRY', 'New', null)
        };

        System.runAs(owner) {
            Test.startTest();
            System.assertNotEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-VIEWED'),
                'A diagnosis upgrade can update a viewed but still active notice.');
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-DISMISSED'));
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-RESOLVED'));
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-EXPIRED-STATUS'));
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-EXPIRED-TIME'));
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-MISSING-EXPIRY'));
            Test.stopTest();
        }
    }

    @IsTest
    static void lookupObservesDismissalAfterEarlierResolution() {
        User owner = recipient(0);
        User_Notification__c item = notice(owner.Id, 'BOUNDARY-FRESH', 'New', Datetime.now().addHours(1));
        insert item;
        System.runAs(owner) {
            Test.startTest();
            System.assertNotEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-FRESH'));
            AEIR_UserNotificationService.dismiss('BOUNDARY-FRESH');
            System.assertEquals(null, AEIR_UserNotificationService.resolveAlert('BOUNDARY-FRESH'),
                'An earlier lookup must not cache stale eligibility.');
            Test.stopTest();
        }
    }

    @IsTest
    static void wakeUpEventContainsNoDiagnosticContent() {
        Aegis_User_Alert__e wakeUpHint = AEIR_UserNotificationService.wakeUpEvent('BOUNDARY-HINT', UserInfo.getUserId());
        System.assertEquals('BOUNDARY-HINT', wakeUpHint.Correlation_Id__c);
        System.assertEquals(String.valueOf(UserInfo.getUserId()), wakeUpHint.Target_User_Id__c);
        System.assertEquals(null, wakeUpHint.Error_Log_Id__c);
        System.assertEquals(null, wakeUpHint.Headline__c);
        System.assertEquals(null, wakeUpHint.Short_Message__c);
        System.assertEquals(null, wakeUpHint.Severity__c);
        System.assertEquals(null, wakeUpHint.Notification_Type__c);
        System.assertEquals(null, wakeUpHint.Action_Available__c);
        System.assertEquals(null, wakeUpHint.Expires_At__c);
    }

    @IsTest
    static void alertHelpRejectsMalformedContextBeforeViewingAnyNotice() {
        String oversized = 'x';
        while (oversized.length() <= 32768) oversized += oversized;
        Test.startTest();
        Integer beforeQueries = Limits.getQueries();
        Integer beforeDml = Limits.getDmlStatements();
        for (String invalidContext : new List<String>{'null', '[]', '1', '{', '{"recordId":42}', '{"pageReference":[]}', oversized}) {
            Boolean rejected = false;
            try {
                AEIR_AegisHeadlessMonitorController.startHelpFromAlert('NO-LOOKUP-SHOULD-RUN', invalidContext, 'A screen issue');
            } catch (AuraHandledException expected) {
                rejected = true;
                System.assert(expected.getMessage().toLowerCase().contains('diagnostic'));
            }
            System.assertEquals(true, rejected);
        }
        System.assertEquals(beforeQueries, Limits.getQueries(), 'Reject invalid context before reading or marking a notice Viewed.');
        System.assertEquals(beforeDml, Limits.getDmlStatements());
        Test.stopTest();
    }
}
