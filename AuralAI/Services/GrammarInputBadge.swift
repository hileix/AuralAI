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
        hasShadow = true
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

    private init() {}

    var centerPoint: NSPoint? {
        guard let frame = panel?.frame else { return nil }
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    func show(for inputFrame: NSRect, onClick: @escaping () -> Void) {
        self.onClick = onClick
        let origin = badgeOrigin(for: inputFrame)
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
        let view = GrammarInputBadgeView(isLoading: true, onClick: onClick)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: badgeSize)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
    }

    func stopLoading() {
        guard let panel, let onClick else { return }
        let view = GrammarInputBadgeView(isLoading: false, onClick: onClick)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: badgeSize)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
    }

    func hide() {
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
}

private struct GrammarInputBadgeView: View {
    let isLoading: Bool
    let onClick: () -> Void

    private var label: String {
        SpeechSettings.shared.language == .chinese ? "使用 AuralAI 优化此输入框" : "Improve this field with AuralAI"
    }

    var body: some View {
        Button(action: onClick) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.08, green: 0.48, blue: 0.94))

                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                if isLoading {
                    Circle()
                        .fill(.black.opacity(0.2))

                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .padding(3)
                .background(.regularMaterial)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .contentShape(Circle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("grammar.input.badge")
        .frame(width: 34, height: 34)
    }
}
