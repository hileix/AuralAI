//
//  GrammarInputBadge.swift
//  AuralAI
//

import AppKit
import SwiftUI

private final class GrammarInputBadgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }
}

final class GrammarInputBadge {
    static let shared = GrammarInputBadge()

    private let badgeSize = NSSize(width: 34, height: 34)
    private var panel: NSPanel?
    private var onClick: (() -> Void)?
    private(set) var isLoading = false

    private init() {}

    var centerPoint: NSPoint? {
        guard let frame = panel?.frame else { return nil }
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    func contains(_ screenPoint: NSPoint) -> Bool {
        panel?.frame.contains(screenPoint) == true
    }

    func show(for inputFrame: NSRect, onClick: @escaping () -> Void) {
        guard GrammarSettings.shared.isInputBadgeVisible else { return }
        let origin = badgeOrigin(for: inputFrame)
        showBadge(at: origin, onClick: onClick)
    }

    func show(at point: NSPoint, onClick: @escaping () -> Void) {
        guard GrammarSettings.shared.isInputBadgeVisible else { return }
        let origin = mouseBadgeOrigin(for: point)
        showBadge(at: origin, onClick: onClick)
    }

    func showLoading(for inputFrame: NSRect, onClick: @escaping () -> Void) {
        let origin = badgeOrigin(for: inputFrame)
        showBadge(at: origin, onClick: onClick)
        showLoading()
    }

    func showLoading(at point: NSPoint, onClick: @escaping () -> Void) {
        let origin = mouseBadgeOrigin(for: point)
        showBadge(at: origin, onClick: onClick)
        showLoading()
    }

    private func showBadge(at origin: NSPoint, onClick: @escaping () -> Void) {
        guard !isLoading else { return }

        self.onClick = onClick
        let frame = NSRect(origin: origin, size: badgeSize)
        let view = GrammarInputBadgeView(isLoading: false, onClick: onClick)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: badgeSize)

        if let panel {
            panel.contentView = hostingView
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            return
        }

        let badgePanel = GrammarInputBadgePanel(contentRect: frame)
        badgePanel.contentView = hostingView
        badgePanel.orderFrontRegardless()
        panel = badgePanel
    }

    func showLoading() {
        guard let panel, let onClick else { return }
        isLoading = true
        let view = GrammarInputBadgeView(isLoading: true, onClick: onClick)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: badgeSize)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
    }

    func stopLoading() {
        isLoading = false
        guard GrammarSettings.shared.isInputBadgeVisible else {
            hide()
            return
        }
        guard let panel, let onClick else { return }
        let view = GrammarInputBadgeView(isLoading: false, onClick: onClick)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: badgeSize)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
    }

    func hide() {
        guard !isLoading else { return }
        panel?.orderOut(nil)
        panel = nil
        onClick = nil
    }

    private func badgeOrigin(for inputFrame: NSRect) -> NSPoint {
        var origin = NSPoint(
            x: inputFrame.minX - badgeSize.width,
            y: inputFrame.maxY
        )

        let center = NSPoint(x: inputFrame.midX, y: inputFrame.midY)
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(center) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        origin.x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - badgeSize.width)
        origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - badgeSize.height)
        return origin
    }

    private func mouseBadgeOrigin(for point: NSPoint) -> NSPoint {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let origin = NSPoint(x: point.x + 12, y: point.y + 12)
        return NSPoint(
            x: min(max(origin.x, screenFrame.minX), screenFrame.maxX - badgeSize.width),
            y: min(max(origin.y, screenFrame.minY), screenFrame.maxY - badgeSize.height)
        )
    }
}

private struct GrammarInputBadgeView: View {
    let isLoading: Bool
    let onClick: () -> Void

    @State private var isHovering = false
    @State private var loadingPhase: CGFloat = 0

    private var label: String {
        SpeechSettings.shared.language == .chinese ? "使用 AuralAI 优化此输入框" : "Improve this field with AuralAI"
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            onClick()
        } label: {
            ZStack {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)

                if isLoading {
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.42),
                            .clear
                        ],
                        startPoint: UnitPoint(x: loadingPhase - 0.62, y: 0.15),
                        endPoint: UnitPoint(x: loadingPhase - 0.08, y: 0.85)
                    )
                    .blendMode(.screen)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(
                color: .black.opacity(isHovering && !isLoading ? 0.3 : 0.22),
                radius: isHovering && !isLoading ? 4 : 3,
                y: isHovering && !isLoading ? 2 : 1
            )
            .scaleEffect(isHovering && !isLoading ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isLoading)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering = $0 }
        .onAppear {
            guard isLoading else { return }
            loadingPhase = 1
        }
        .animation(
            isLoading
                ? .linear(duration: 1.25).repeatForever(autoreverses: true)
                : .default,
            value: loadingPhase
        )
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("grammar.input.badge")
        .frame(width: 34, height: 34)
    }
}
