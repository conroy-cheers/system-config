import CoreGraphics
import Foundation

/// Monitors mouse position by polling CoreGraphics on a timer.
/// This avoids AppKit main-loop quirks for detached background processes.
public final class EventTapMonitor {
    private let stateMachine: BarStateMachine
    private let debugLog: ((String) -> Void)?
    private var pollTimer: DispatchSourceTimer?
    private let pollInterval: TimeInterval
    private let pollQueue: DispatchQueue
    private var pollCount = 0
    private var wasMouseDown = false

    public init(
        stateMachine: BarStateMachine,
        debugLog: ((String) -> Void)? = nil,
        pollInterval: TimeInterval = 0.016,
        pollQueue: DispatchQueue = DispatchQueue(label: "sketchybar-toggle.poll", qos: .userInteractive)
    ) {
        self.stateMachine = stateMachine
        self.debugLog = debugLog
        self.pollInterval = pollInterval
        self.pollQueue = pollQueue
    }

    /// Start monitoring mouse position. Always returns true.
    @discardableResult
    public func start() -> Bool {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.pollMousePosition()
        }
        pollTimer = timer
        timer.resume()
        debugLog?("polling started at \(Int(1.0 / pollInterval)) Hz")
        return true
    }

    public func stop() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func pollMousePosition() {
        guard let mousePoint = CGEvent(source: nil)?.location else {
            return
        }

        guard let screenOriginY = screenOriginYForPoint(mousePoint) else {
            return
        }

        let distanceFromTop = mousePoint.y - screenOriginY

        pollCount += 1
        if distanceFromTop < 60 || pollCount <= 3 || pollCount % 1000 == 0 {
            debugLog?("poll#\(pollCount) dist=\(Int(distanceFromTop)) state=\(stateMachine.state)")
        }

        let isMouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        if isMouseDown && !wasMouseDown {
            debugLog?("poll#\(pollCount) click detected dist=\(Int(distanceFromTop)) state=\(stateMachine.state)")
            stateMachine.handleMouseClick(distanceFromTop: distanceFromTop)
        }
        wasMouseDown = isMouseDown

        stateMachine.handleMousePosition(distanceFromTop: distanceFromTop)
    }

    private func screenOriginYForPoint(_ point: CGPoint) -> CGFloat? {
        for display in onlineDisplays() {
            let bounds = CGDisplayBounds(display).insetBy(dx: -1, dy: -1)
            if bounds.contains(point) {
                return bounds.minY
            }
        }
        return nil
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else {
            return []
        }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return []
        }

        return Array(displays.prefix(Int(count)))
    }
}
