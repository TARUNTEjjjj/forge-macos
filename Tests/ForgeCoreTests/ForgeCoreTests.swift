import XCTest
import ForgeCheckSupport

final class ForgeCoreTests: XCTestCase {
    func testCatalogCacheSurvivesRestartWithoutTouchingProgress() throws { try ForgeCoreChecks.run("testCatalogCacheSurvivesRestartWithoutTouchingProgress") }
    func testCatalogCacheRejectsAndRepairsDamagedFiles() throws { try ForgeCoreChecks.run("testCatalogCacheRejectsAndRepairsDamagedFiles") }
    func testCatalogCacheInvalidSavePreservesLastGoodBytes() throws { try ForgeCoreChecks.run("testCatalogCacheInvalidSavePreservesLastGoodBytes") }
    func testCatalogCacheFailedWritePreservesLastGoodBytes() throws { try ForgeCoreChecks.run("testCatalogCacheFailedWritePreservesLastGoodBytes") }
    func testCatalogCacheRejectsSymlinksAndDirectories() throws { try ForgeCoreChecks.run("testCatalogCacheRejectsSymlinksAndDirectories") }
    func testCatalogCacheKeepsNewestCollection() throws { try ForgeCoreChecks.run("testCatalogCacheKeepsNewestCollection") }
    func testRemoteGitHubCatalogDownloadsAndValidates() throws { try ForgeCoreChecks.run("testRemoteGitHubCatalogDownloadsAndValidates") }
    func testRemoteGitHubCatalogRejectsUnsafeResponses() throws { try ForgeCoreChecks.run("testRemoteGitHubCatalogRejectsUnsafeResponses") }
    func testGitHubCatalogAgeHonesty() throws { try ForgeCoreChecks.run("testGitHubCatalogAgeHonesty") }

    func testBundledGitHubCatalogAndSearch() throws { try ForgeCoreChecks.run("testBundledGitHubCatalogAndSearch") }
    func testGitHubCatalogRejectsUnsafeLinksAndDuplicateEntries() throws { try ForgeCoreChecks.run("testGitHubCatalogRejectsUnsafeLinksAndDuplicateEntries") }

    func testBundledCurriculumHasCompleteLearningPath() throws { try ForgeCoreChecks.run("testBundledCurriculumHasCompleteLearningPath") }
    func testNewStoreIsEmptyWithoutCreatingFile() throws { try ForgeCoreChecks.run("testNewStoreIsEmptyWithoutCreatingFile") }
    func testProgressSurvivesNewStoreInstanceAndBackupRoundTrip() throws { try ForgeCoreChecks.run("testProgressSurvivesNewStoreInstanceAndBackupRoundTrip") }
    func testImportOnlyValidatesUntilUserChoosesToRestore() throws { try ForgeCoreChecks.run("testImportOnlyValidatesUntilUserChoosesToRestore") }
    func testMalformedAndTruncatedBackupsAreRejected() throws { try ForgeCoreChecks.run("testMalformedAndTruncatedBackupsAreRejected") }
    func testUnknownVersionsAreRejected() throws { try ForgeCoreChecks.run("testUnknownVersionsAreRejected") }
    func testProgressForLessonsOutsideTheCurriculumIsKept() throws { try ForgeCoreChecks.run("testProgressForLessonsOutsideTheCurriculumIsKept") }
    func testFieldsFromOtherForgeVersionsAreKept() throws { try ForgeCoreChecks.run("testFieldsFromOtherForgeVersionsAreKept") }
    func testNumbersFromOtherForgeVersionsAreKeptExactlyOrLeftOut() throws { try ForgeCoreChecks.run("testNumbersFromOtherForgeVersionsAreKeptExactlyOrLeftOut") }
    func testSessionDurationAndDuplicateIDsAreValidated() throws { try ForgeCoreChecks.run("testSessionDurationAndDuplicateIDsAreValidated") }
    func testInvalidSessionDatesAreRejected() throws { try ForgeCoreChecks.run("testInvalidSessionDatesAreRejected") }
    func testTextLimitsCountUTF8Bytes() throws { try ForgeCoreChecks.run("testTextLimitsCountUTF8Bytes") }
    func testOversizedBackupRejectedBeforeDecoding() throws { try ForgeCoreChecks.run("testOversizedBackupRejectedBeforeDecoding") }
    func testSessionLimitWithLongReflectionsSavesAndRestores() throws { try ForgeCoreChecks.run("testSessionLimitWithLongReflectionsSavesAndRestores") }
    func testInvalidSavePreservesPreviousSnapshotBytes() throws { try ForgeCoreChecks.run("testInvalidSavePreservesPreviousSnapshotBytes") }
    func testDamagedFileIsPreservedAndNotSilentlyReset() throws { try ForgeCoreChecks.run("testDamagedFileIsPreservedAndNotSilentlyReset") }
    func testSaveRechecksFilesChangedOutsideTheStore() throws { try ForgeCoreChecks.run("testSaveRechecksFilesChangedOutsideTheStore") }
    func testOlderProgressNeverReplacesProgressSavedElsewhere() throws { try ForgeCoreChecks.run("testOlderProgressNeverReplacesProgressSavedElsewhere") }
    func testExplicitRecoveryPreservesDamagedOriginalAndRestoresBackup() throws { try ForgeCoreChecks.run("testExplicitRecoveryPreservesDamagedOriginalAndRestoresBackup") }
    func testRestoreKeepsADatedRecoveryCopyOnlyWhenThereIsAFile() throws { try ForgeCoreChecks.run("testRestoreKeepsADatedRecoveryCopyOnlyWhenThereIsAFile") }
    func testInvalidRecoveryDoesNotTouchExistingData() throws { try ForgeCoreChecks.run("testInvalidRecoveryDoesNotTouchExistingData") }
    func testReadOnlyDestinationFailsWithoutReportingSuccess() throws { try ForgeCoreChecks.run("testReadOnlyDestinationFailsWithoutReportingSuccess") }
    func testCalendarTotalsUseLearnersTimezone() throws { try ForgeCoreChecks.run("testCalendarTotalsUseLearnersTimezone") }
    func testDailyTotalsPreserveOrderAndTimezone() throws { try ForgeCoreChecks.run("testDailyTotalsPreserveOrderAndTimezone") }
    func testDailyTotalsHandleDaylightSavingTransitions() throws { try ForgeCoreChecks.run("testDailyTotalsHandleDaylightSavingTransitions") }
    func testDailyTotalsHandleMaximumSessionHistory() throws { try ForgeCoreChecks.run("testDailyTotalsHandleMaximumSessionHistory") }
    func testSessionSearchCombinesTermsLessonsAndDateBounds() throws { try ForgeCoreChecks.run("testSessionSearchCombinesTermsLessonsAndDateBounds") }
}
