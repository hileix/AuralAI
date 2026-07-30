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

    private let statusSize = NSSize(width: 268, height: 60)
    private var window: NSWindow?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var anchorPoint: NSPoint?

    private init() {}

    func showLoading() {
        showLoading(at: NSEvent.mouseLocation)
    }

    func showLoading(at anchor: NSPoint) {
        DispatchQueue.main.async {
            self.dismiss()

            self.anchorPoint = anchor
            self.showStatus(GrammarStatusView(state: .loading), at: anchor)
        }
    }

    func showSuccess() {
        DispatchQueue.main.async {
            self.showStatus(
                GrammarStatusView(state: .success),
                at: self.anchorPoint ?? NSEvent.mouseLocation
            )
            self.dismissAfterDelay()
        }
    }

    func showError() {
        DispatchQueue.main.async {
            self.showStatus(
                GrammarStatusView(state: .error),
                at: self.anchorPoint ?? NSEvent.mouseLocation
            )
            self.dismissAfterDelay()
        }
    }

    func showResults(response: GrammarAIResponse, onSelect: @escaping (String) -> Void) {
        showResults(response: response, at: nil, onSelect: onSelect)
    }

    func showResults(
        response: GrammarAIResponse,
        at previewAnchor: NSPoint?,
        onSelect: @escaping (String) -> Void
    ) {
        DispatchQueue.main.async {
            self.dismiss()

            let anchor = previewAnchor ?? self.anchorPoint ?? NSEvent.mouseLocation
            let view = GrammarResultsPopupView(
                response: response,
                onSelect: { [weak self] selected in
                    self?.dismiss()
                    onSelect(selected)
                },
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            )

            let hostingView = NSHostingView(rootView: view)
            hostingView.setFrameSize(hostingView.fittingSize)
            let contentSize = hostingView.fittingSize

            let origin = self.positionedOrigin(anchor: anchor, size: contentSize)

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

    private func showStatus<V: View>(_ view: V, at anchor: NSPoint) {
        let hostingView = NSHostingView(rootView: view)

        if let window {
            window.contentView = hostingView
            window.setContentSize(statusSize)
            window.orderFrontRegardless()
            return
        }

        let statusWindow = NSWindow(
            contentRect: NSRect(
                origin: positionedOrigin(anchor: anchor, size: statusSize),
                size: statusSize
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        statusWindow.level = .floating
        statusWindow.isOpaque = false
        statusWindow.backgroundColor = .clear
        statusWindow.hasShadow = false
        statusWindow.ignoresMouseEvents = true
        statusWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        statusWindow.contentView = hostingView
        statusWindow.orderFrontRegardless()

        window = statusWindow
    }

    private func positionedOrigin(anchor: NSPoint, size: NSSize) -> NSPoint {
        let screenFrame = NSScreen.screens.first(where: { $0.visibleFrame.contains(anchor) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let gap: CGFloat = 12
        let margin: CGFloat = 12

        var x = anchor.x + gap
        if x + size.width > screenFrame.maxX - margin {
            x = anchor.x - size.width - gap
        }
        x = min(max(x, screenFrame.minX + margin), screenFrame.maxX - size.width - margin)

        var y = anchor.y - size.height - gap
        if y < screenFrame.minY + margin {
            y = anchor.y + gap
        }
        y = min(max(y, screenFrame.minY + margin), screenFrame.maxY - size.height - margin)

        return NSPoint(x: x, y: y)
    }

    private func dismissAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
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

private struct GrammarStatusView: View {
    enum State {
        case loading
        case success
        case error
    }

    let state: State

    private var copy: GrammarPopupCopy { .current }

    private var title: String {
        switch state {
        case .loading:
            return copy.improvingText
        case .success:
            return copy.appliedText
        case .error:
            return copy.errorText
        }
    }

    private var color: Color {
        switch state {
        case .loading:
            return .accentColor
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var accessibilityIdentifier: String {
        switch state {
        case .loading:
            return "grammar.status.loading"
        case .success:
            return "grammar.status.success"
        case .error:
            return "grammar.status.error"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.12))

                switch state {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                        .tint(color)
                case .success:
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                case .error:
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 36, height: 36)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 268, height: 60)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct GrammarResultsPopupView: View {
    let response: GrammarAIResponse
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    private var copy: GrammarPopupCopy { .current }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(copy.resultsTitle)
                        .font(.headline)
                    Text(copy.optionCount(response.options.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(Color.primary.opacity(0.06))
                .clipShape(Circle())
                .help(copy.closeLabel)
                .accessibilityLabel(copy.closeLabel)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let translation = response.translation {
                        GrammarResultSection(
                            title: copy.translationTitle,
                            systemImage: "character.book.closed",
                            color: .blue,
                            text: translation
                        )
                    }

                    if let errors = response.errors {
                        GrammarResultSection(
                            title: copy.errorsTitle,
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange,
                            text: errors
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label(copy.chooseVersionTitle, systemImage: "text.badge.checkmark")
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)

                        ForEach(Array(response.options.enumerated()), id: \.offset) { index, option in
                            GrammarOptionButton(
                                index: index + 1,
                                title: copy.optionTitle(index + 1),
                                text: option,
                                onSelect: onSelect
                            )
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 7)
    }
}

private struct GrammarResultSection: View {
    let title: String
    let systemImage: String
    let color: Color
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 1)
        }
    }
}

private struct GrammarOptionButton: View {
    let index: Int
    let title: String
    let text: String
    let onSelect: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { onSelect(text) }) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 25, height: 25)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(text)
                        .font(.body)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isHovered ? 1 : 0.35)
                    .padding(.top, 3)
            }
            .padding(12)
            .background(Color.accentColor.opacity(isHovered ? 0.12 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(isHovered ? 0.32 : 0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("\(title). \(text)")
        .accessibilityIdentifier("grammar.results.option.\(index)")
    }
}

private struct GrammarPopupCopy {
    let improvingText: String
    let appliedText: String
    let errorText: String
    let resultsTitle: String
    let translationTitle: String
    let errorsTitle: String
    let chooseVersionTitle: String
    let closeLabel: String
    let optionLabel: String
    let optionsLabel: String

    static var current: GrammarPopupCopy {
        switch SpeechSettings.shared.language {
        case .english:
            return GrammarPopupCopy(
                improvingText: "Improving selected text",
                appliedText: "Text replaced",
                errorText: "Couldn't improve text",
                resultsTitle: "Writing suggestions",
                translationTitle: "Translation",
                errorsTitle: "What to fix",
                chooseVersionTitle: "Choose a version",
                closeLabel: "Close",
                optionLabel: "Option",
                optionsLabel: "options"
            )
        case .chinese:
            return GrammarPopupCopy(
                improvingText: "正在优化所选文本",
                appliedText: "文本已替换",
                errorText: "无法优化文本",
                resultsTitle: "写作建议",
                translationTitle: "翻译",
                errorsTitle: "需要修改",
                chooseVersionTitle: "选择一个版本",
                closeLabel: "关闭",
                optionLabel: "选项",
                optionsLabel: "个选项"
            )
        }
    }

    func optionTitle(_ index: Int) -> String {
        "\(optionLabel) \(index)"
    }

    func optionCount(_ count: Int) -> String {
        if SpeechSettings.shared.language == .chinese {
            return "\(count) \(optionsLabel)"
        }
        return "\(count) \(count == 1 ? "option" : optionsLabel)"
    }
}
