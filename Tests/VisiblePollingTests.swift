import Foundation
import Testing
@testable import GoveeCore

@MainActor
struct VisiblePollingTests {
    @Test func closedSurfaceDoesNotStartRequests() async throws {
        var calls = 0
        let polling = VisiblePolling(interval: .milliseconds(10), openingDelay: .zero) { calls += 1 }
        polling.refreshNow()
        try await Task.sleep(for: .milliseconds(40))
        #expect(calls == 0)
    }

    @Test func closingStopsRepeatedPollingAndReopeningResumes() async throws {
        var calls = 0
        let polling = VisiblePolling(interval: .milliseconds(20), openingDelay: .zero) { calls += 1 }
        defer { polling.setVisible(false) }
        polling.setVisible(true)
        try await waitUntil { calls >= 2 }
        polling.setVisible(false)
        let closedCount = calls
        try await Task.sleep(for: .milliseconds(80))
        #expect(calls == closedCount)
        polling.setVisible(true)
        try await waitUntil { calls > closedCount }
    }

    @Test func repeatedOpenNotificationsDoNotDuplicateRequests() async throws {
        var calls = 0
        let polling = VisiblePolling(interval: .seconds(60), openingDelay: .zero) { calls += 1 }
        defer { polling.setVisible(false) }
        polling.setVisible(true)
        polling.setVisible(true)
        polling.setVisible(true)
        try await waitUntil { calls >= 1 }
        try await Task.sleep(for: .milliseconds(30))
        #expect(calls == 1)
    }

    @Test func rapidReopenCancelsTheOldRequestBeforeStartingAnother() async throws {
        var calls = 0
        var active = 0
        var maxActive = 0
        var cancellations = 0
        let polling = VisiblePolling(interval: .seconds(60), openingDelay: .zero) {
            calls += 1
            active += 1
            maxActive = max(maxActive, active)
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancellations += 1 }
            active -= 1
        }
        defer { polling.setVisible(false) }
        polling.setVisible(true)
        try await waitUntil { active == 1 }
        polling.setVisible(false)
        polling.setVisible(true)
        try await waitUntil { calls == 2 }
        #expect(cancellations == 1)
        #expect(maxActive == 1)
        polling.setVisible(false)
        try await waitUntil { active == 0 }
        #expect(cancellations == 2)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(condition(), "Timed out waiting for the polling lifecycle")
    }
}
