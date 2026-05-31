//
//  FloatingToolbarPanel.swift
//  RedPulse
//
//  macOS-only: a lightweight NSPanel that floats above all windows,
//  follows the mouse cursor, and hosts the SelectionToolbarView.
//  Not constrained to the app window — works system-wide.
//

#if os(macOS)

import SwiftUI
import AppKit

// MARK: - Panel Manager (global singleton)

@MainActor
final class FloatingToolbarPanel {
    static let shared = FloatingToolbarPanel()

    private var panel: NSPanel?
    private var hostingView: NSView?
    private var panelSize: NSSize = .zero
    private var mouseMonitor: Any?      // NSEvent monitor for mouse-drag events
    private var pollingTimer: Timer?     // Timer-based polling for mouseMoved
    private var viewModel: SelectionToolbarViewModel?
    private var lastUpdateTime: Date = .distantPast

    private init() {}

    // MARK: - Show / Hide

    func show(with viewModel: SelectionToolbarViewModel) {
        // Use the selection's screen position (below selected text) if available,
        // otherwise fall back to the current mouse cursor location.
        var location = NSEvent.mouseLocation
        if let sel = viewModel.selectionScreenOrigin, sel != .zero {
            location = sel  // place below selected text
        }
        // If already showing with a different VM, dismiss first
        if panel != nil {
            dismiss()
        }

        self.viewModel = viewModel

        let toolbarView = SelectionToolbarView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: AnyView(toolbarView))
        // Let the SwiftUI view size itself naturally
        hosting.setFrameSize(hosting.fittingSize)
        let size = hosting.fittingSize
        self.hostingView = hosting
        self.panelSize = size

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        // Position below the selected text (centered), or near cursor as fallback
        let origin = NSPoint(
            x: location.x + 16,
            y: location.y - panelSize.height - 8
        )
        panel.setFrameOrigin(sanitizeOrigin(origin, size: panelSize))
        panel.orderFront(nil)

        self.panel = panel

        // Start tracking mouse movement
        startMouseTracking()
    }

    func updatePosition(to mouseLocation: NSPoint) {
        guard let panel else { return }
        // Throttle: don't reposition more often than every ~60fps frame
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) > 1.0 / 60.0 else { return }
        lastUpdateTime = now
        // Same offset as show(): 16pt right, 8pt below cursor/selection
        let newOrigin = sanitizeOrigin(
            NSPoint(x: mouseLocation.x + 16, y: mouseLocation.y - panelSize.height - 8),
            size: panelSize
        )
        // Skip no-op moves
        guard abs(panel.frame.origin.x - newOrigin.x) > 1 || abs(panel.frame.origin.y - newOrigin.y) > 1 else { return }
        panel.setFrameOrigin(newOrigin)
    }

    func dismiss() {
        stopMouseTracking()
        panel?.close()
        panel = nil
        hostingView = nil
        viewModel = nil
    }

    var isVisible: Bool { panel != nil }

    // MARK: - Mouse tracking (polling-based)

    /// On macOS, `.mouseMoved` events are not reliably dispatched to global
    /// monitors. Instead, we poll `NSEvent.mouseLocation` at ~30fps via a
    /// background timer. This catches all cursor movement regardless of window
    /// focus or tracking area setup.
    private func startMouseTracking() {
        stopMouseTracking()

        // Also track mouse-drag for when user holds a button and moves
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            guard let self else { return event }
            self.updatePosition(to: NSEvent.mouseLocation)
            return event
        }

        // Polling timer: 30fps (33ms interval) — updates even when no
        // mouse-drag is happening (e.g. hovering after text selection).
        // Use RunLoop.main to guarantee the timer runs on the main thread's
        // common run-loop mode (includes scrolling / event tracking).
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.panel != nil else { return }
            let loc = NSEvent.mouseLocation
            // log for debugging
            // NSLog("[toolbar] mouse=\(loc.x),\(loc.y) panel=\(self.panel!.frame.origin.x),\(self.panel!.frame.origin.y)")
            self.updatePosition(to: loc)
        }
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Helpers

    /// Keep the panel within the visible screen bounds.
    private func sanitizeOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return origin }
        let frame = screen.visibleFrame
        var x = origin.x
        var y = origin.y
        if x + size.width > frame.maxX { x = frame.maxX - size.width - 8 }
        if x < frame.minX { x = frame.minX + 8 }
        if y + size.height > frame.maxY { y = frame.maxY - size.height - 8 }
        if y < frame.minY { y = frame.minY + 8 }
        return NSPoint(x: x, y: y)
    }
}

// MARK: - SwiftUI integration helper

/// On macOS, wraps a SelectionToolbarView so it can be shown in the
/// FloatingToolbarPanel instead of as an inline overlay.
struct MacSelectionToolbarBridge: View {
    @Bindable var viewModel: SelectionToolbarViewModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: viewModel.isVisible) { _, visible in
                if visible {
                    // Defer panel creation to avoid SwiftUI rendering assertion
                    DispatchQueue.main.async {
                        FloatingToolbarPanel.shared.show(with: viewModel)
                    }
                } else {
                    FloatingToolbarPanel.shared.dismiss()
                }
            }
            .onDisappear {
                FloatingToolbarPanel.shared.dismiss()
            }
    }
}

#endif
