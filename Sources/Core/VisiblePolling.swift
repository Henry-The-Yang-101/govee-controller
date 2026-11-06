import Foundation

/// Owns exactly one polling loop. A closed surface has no timer or request left running.
@MainActor
final class VisiblePolling {
    private(set) var isVisible = false
    private var task: Task<Void, Never>?
    private let interval: Duration
    private let openingDelay: Duration
    private let refresh: @MainActor () async -> Void

    init(interval: Duration = .seconds(30), openingDelay: Duration = .milliseconds(150),
         refresh: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.openingDelay = openingDelay
        self.refresh = refresh
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible { restart() }
        else { task?.cancel() }
    }

    func refreshNow() {
        guard isVisible else { return }
        restart()
    }

    private func restart() {
        let previous = task
        previous?.cancel()
        task = Task { [refresh, interval, openingDelay] in
            // Let an interrupted URLSession request unwind before starting another loop.
            // This also prevents an immediate reopen from losing its first refresh.
            await previous?.value
            do { try await Task.sleep(for: openingDelay) } catch { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    deinit { task?.cancel() }
}
