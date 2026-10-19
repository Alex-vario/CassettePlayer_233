import SwiftUI
import AppKit

final class WindowGeometryManager: ObservableObject {

    private enum Mode {
        case main
        case mini
    }

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var mode: Mode = .main
    private var originalStyleMask: NSWindow.StyleMask?
    private var originalTitleVisibility: NSWindow.TitleVisibility = .visible
    private var originalTitlebarAppearsTransparent = false
    private var originalMovableByWindowBackground = false

    private let mainFrameKey = "CassettePlayer.MainWindow.Frame"
    private let miniFrameKey = "CassettePlayer.MiniPlayer.Frame"

    func attach(
        _ window: NSWindow,
        alwaysOnTop: Bool
    ) {
        if self.window === window {
            applyWindowLevel(alwaysOnTop: alwaysOnTop)
            return
        }

        removeObservers()
        self.window = window
        mode = .main
        originalStyleMask = window.styleMask
        originalTitleVisibility = window.titleVisibility
        originalTitlebarAppearsTransparent = window.titlebarAppearsTransparent
        originalMovableByWindowBackground = window.isMovableByWindowBackground

        for name in [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification
        ] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.saveCurrentFrame()
            }

            observers.append(observer)
        }

        if let savedFrame = storedFrame(for: .main),
           isVisibleOnScreen(savedFrame) {
            window.setFrame(savedFrame, display: true)
        }

        applyWindowLevel(alwaysOnTop: alwaysOnTop)
        saveCurrentFrame()
    }

    func switchMode(
        toMini: Bool,
        alwaysOnTop: Bool
    ) {
        guard let window else { return }

        let targetMode: Mode = toMini ? .mini : .main

        if isSameMode(targetMode) {
            applyWindowLevel(alwaysOnTop: alwaysOnTop)
            return
        }

        saveCurrentFrame()
        let previousFrame = window.frame
        mode = targetMode
        applyMiniTitlebarMode(isMini: toMini)

        let targetSize = toMini
            ? NSSize(width: 520, height: 60)
            : NSSize(width: 1024, height: 283)

        if let savedFrame = storedFrame(for: targetMode),
           isVisibleOnScreen(savedFrame) {
            var targetFrame = savedFrame

            if toMini {
                // Force the current Mini Player size, even if an older height was saved.
                targetFrame.size = targetSize
                targetFrame.origin.y = savedFrame.maxY - targetFrame.height
            }

            window.setFrame(targetFrame, display: true, animate: true)
        } else {
            window.setContentSize(targetSize)

            var targetFrame = window.frame
            targetFrame.origin.x = previousFrame.minX
            targetFrame.origin.y = previousFrame.maxY - targetFrame.height

            if !isVisibleOnScreen(targetFrame) {
                targetFrame.origin.x = 80
                targetFrame.origin.y = max(
                    80,
                    (NSScreen.main?.visibleFrame.maxY ?? 800) - targetFrame.height - 80
                )
            }

            window.setFrame(targetFrame, display: true, animate: true)
        }

        applyWindowLevel(alwaysOnTop: alwaysOnTop)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.saveCurrentFrame()
        }
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        applyWindowLevel(alwaysOnTop: enabled)
    }

    private func applyMiniTitlebarMode(isMini: Bool) {
        guard let window else { return }

        if isMini {
            // Remove the native title bar and its traffic-light buttons only in Mini Player.
            // The original style is restored when returning to the main player.
            window.styleMask.remove(.titled)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
        } else {
            if let originalStyleMask {
                window.styleMask = originalStyleMask
            }
            window.titleVisibility = originalTitleVisibility
            window.titlebarAppearsTransparent = originalTitlebarAppearsTransparent
            window.isMovableByWindowBackground = originalMovableByWindowBackground
        }
    }

    private func isSameMode(_ other: Mode) -> Bool {
        switch (mode, other) {
        case (.main, .main), (.mini, .mini):
            return true
        default:
            return false
        }
    }

    private func applyWindowLevel(alwaysOnTop: Bool) {
        guard let window else { return }

        if case .mini = mode, alwaysOnTop {
            window.level = .floating
        } else {
            window.level = .normal
        }
    }

    private func saveCurrentFrame() {
        guard let window else { return }

        let key: String
        switch mode {
        case .main:
            key = mainFrameKey
        case .mini:
            key = miniFrameKey
        }

        UserDefaults.standard.set(
            NSStringFromRect(window.frame),
            forKey: key
        )
    }

    private func storedFrame(for mode: Mode) -> NSRect? {
        let key: String
        switch mode {
        case .main:
            key = mainFrameKey
        case .mini:
            key = miniFrameKey
        }

        guard let value = UserDefaults.standard.string(forKey: key) else {
            return nil
        }

        let frame = NSRectFromString(value)
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }

        return frame
    }

    private func isVisibleOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let intersection = frame.intersection(screen.visibleFrame)
            return !intersection.isNull
                && intersection.width >= 100
                && intersection.height >= 60
        }
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        removeObservers()
    }
}

struct WindowAccessor: NSViewRepresentable {

    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)

        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }

        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
    }
}
