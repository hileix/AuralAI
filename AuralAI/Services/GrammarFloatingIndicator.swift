//
//  GrammarFloatingIndicator.swift
//  AuralAI
//

import AppKit
import SwiftUI

private class GrammarClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

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
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }
}

final class GrammarFloatingIndicator {
    static let shared = GrammarFloatingIndicator()

    private var window: NSWindow?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var anchorPoint: NSPoint?

    private init() {}

    func showLoading() {
        DispatchQueue.main.async {
            self.dismiss()

            let mouseLocation = NSEvent.mouseLocation
            self.anchorPoint = mouseLocation
            let size: CGFloat = 48

            let window = NSWindow(
                contentRect: NSRect(x: mouseLocation.x + 8, y: mouseLocation.y - size - 8, width: size, height: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.contentView = NSHostingView(rootView: GrammarLoadingView())
            window.orderFrontRegardless()

            self.window = window
        }
    }

    func showSuccess() {
        DispatchQueue.main.async {
            self.replaceContent(GrammarResultView(symbol: "checkmark.circle.fill", color: .green))
            self.dismissAfterDelay()
        }
    }

    func showError() {
        DispatchQueue.main.async {
            self.replaceContent(GrammarResultView(symbol: "xmark.circle.fill", color: .red))
            self.dismissAfterDelay()
        }
    }

    func showResults(response: GrammarAIResponse, onSelect: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            self.dismiss()

            let anchor = self.anchorPoint ?? NSEvent.mouseLocation
            let view = GrammarResultsPopupView(
                response: response,
                onSelect: { [weak self] selected in
                    self?.dismiss()
                    onSelect(selected)
                }
            )

            let hostingView = NSHostingView(rootView: view)
            hostingView.setFrameSize(hostingView.fittingSize)
            let contentSize = hostingView.fittingSize

            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            var origin = NSPoint(
                x: anchor.x + 8,
                y: anchor.y - contentSize.height - 8
            )
            if origin.x + contentSize.width > screenFrame.maxX {
                origin.x = anchor.x - contentSize.width - 8
            }
            if origin.y < screenFrame.minY {
                origin.y = anchor.y + 8
            }

            let panel = GrammarClickablePanel(contentRect: NSRect(origin: origin, size: contentSize))
            panel.hasShadow = false
            panel.contentView = hostingView
            panel.orderFrontRegardless()

            self.window = panel
            self.anchorPoint = nil
            self.installDismissMonitors()
        }
    }

    func dismiss() {
        removeMonitors()
        window?.orderOut(nil)
        window = nil
    }

    private func replaceContent<V: View>(_ view: V) {
        guard let window else { return }
        window.contentView = NSHostingView(rootView: view)
    }

    private func dismissAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.dismiss()
        }
    }

    private func installDismissMonitors() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let window = self.window else { return }
            if !window.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}

private struct GrammarLoadingView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)

            ProgressView()
                .scaleEffect(0.8)
                .controlSize(.small)
        }
        .frame(width: 48, height: 48)
    }
}

private struct GrammarResultView: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)

            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(color)
        }
        .frame(width: 48, height: 48)
    }
}

private struct GrammarResultsPopupView: View {
    let response: GrammarAIResponse
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let translation = response.translation {
                        GrammarResultSection(title: "翻译", text: translation)
                    }

                    if let errors = response.errors {
                        GrammarResultSection(title: "错误", text: errors)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择一个版本")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(Array(response.options.enumerated()), id: \.offset) { index, option in
                            GrammarOptionButton(index: index + 1, text: option, onSelect: onSelect)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 400, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
    }
}

private struct GrammarResultSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.body)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }
}

private struct GrammarOptionButton: View {
    let index: Int
    let text: String
    let onSelect: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { onSelect(text) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Option \(index)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.body)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(isHovered ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(isHovered ? 0.35 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
