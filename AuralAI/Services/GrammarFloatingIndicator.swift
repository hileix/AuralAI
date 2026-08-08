//
//  GrammarFloatingIndicator.swift
//  AuralAI
//

import AppKit
import Combine
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
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }
}

private final class GrammarResultsModel: ObservableObject {
    @Published var response: GrammarOptimizationResult
    @Published var isStreaming: Bool

    init(response: GrammarOptimizationResult, isStreaming: Bool) {
        self.response = response
        self.isStreaming = isStreaming
    }
}

final class GrammarFloatingIndicator {
    static let shared = GrammarFloatingIndicator()

    private let loadingSize = NSSize(width: 32, height: 32)
    private let statusSize = NSSize(width: 268, height: 60)
    private var window: NSWindow?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var anchorPoint: NSPoint?
    private var resultsModel: GrammarResultsModel?
    private var onUserDismiss: (() -> Void)?

    private init() {}

    func showLoading() {
        showLoading(at: NSEvent.mouseLocation)
    }

    func showLoading(at anchor: NSPoint) {
        DispatchQueue.main.async {
            self.dismiss()

            self.anchorPoint = anchor
            self.showStatus(GrammarLoadingView(), size: self.loadingSize, at: anchor)
        }
    }

    func showSuccess() {
        showSuccess(at: nil)
    }

    func showSuccess(at anchor: NSPoint?) {
        DispatchQueue.main.async {
            self.showStatus(
                GrammarStatusView(state: .success),
                size: self.statusSize,
                at: anchor ?? self.anchorPoint ?? NSEvent.mouseLocation
            )
            self.dismissAfterDelay()
        }
    }

    func showError() {
        showError(at: nil)
    }

    func showError(at anchor: NSPoint?) {
        DispatchQueue.main.async {
            self.showStatus(
                GrammarStatusView(state: .error),
                size: self.statusSize,
                at: anchor ?? self.anchorPoint ?? NSEvent.mouseLocation
            )
            self.dismissAfterDelay()
        }
    }

    func showResults(response: GrammarOptimizationResult, onSelect: @escaping (String) -> Void) {
        showResults(response: response, at: nil, onSelect: onSelect)
    }

    func showResults(
        response: GrammarOptimizationResult,
        at previewAnchor: NSPoint?,
        onSelect: @escaping (String) -> Void
    ) {
        showResults(
            response: response,
            at: previewAnchor,
            onSelect: onSelect,
            onUserDismiss: nil
        )
    }

    func showResults(
        response: GrammarOptimizationResult,
        at previewAnchor: NSPoint?,
        onSelect: @escaping (String) -> Void,
        onUserDismiss: (() -> Void)?,
        onPresented: (() -> Void)? = nil
    ) {
        showResults(
            response: response,
            at: previewAnchor,
            isStreaming: false,
            onSelect: onSelect,
            onUserDismiss: onUserDismiss,
            onPresented: onPresented
        )
    }

    func showStreamingResults(
        response: GrammarOptimizationResult,
        onSelect: @escaping (String) -> Void,
        onUserDismiss: @escaping () -> Void
    ) {
        showStreamingResults(
            response: response,
            at: nil,
            onSelect: onSelect,
            onUserDismiss: onUserDismiss
        )
    }

    func showStreamingResults(
        response: GrammarOptimizationResult,
        at previewAnchor: NSPoint?,
        onSelect: @escaping (String) -> Void,
        onUserDismiss: @escaping () -> Void,
        onPresented: (() -> Void)? = nil
    ) {
        showResults(
            response: response,
            at: previewAnchor,
            isStreaming: true,
            onSelect: onSelect,
            onUserDismiss: onUserDismiss,
            onPresented: onPresented
        )
    }

    func updateResults(response: GrammarOptimizationResult, isStreaming: Bool) {
        DispatchQueue.main.async {
            self.resultsModel?.response = response
            self.resultsModel?.isStreaming = isStreaming
        }
    }

    private func showResults(
        response: GrammarOptimizationResult,
        at previewAnchor: NSPoint?,
        isStreaming: Bool,
        onSelect: @escaping (String) -> Void,
        onUserDismiss: (() -> Void)?,
        onPresented: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            self.dismiss()

            let anchor = previewAnchor ?? self.anchorPoint ?? NSEvent.mouseLocation
            let isPinned = GrammarSettings.shared.isResultsPopupPinned
            let model = GrammarResultsModel(response: response, isStreaming: isStreaming)
            self.resultsModel = model
            self.onUserDismiss = onUserDismiss
            let view = GrammarResultsPopupView(
                model: model,
                isPinned: isPinned,
                onSelect: { [weak self] selected in
                    self?.onUserDismiss = nil
                    self?.dismiss()
                    onSelect(selected)
                },
                onDismiss: { [weak self] in
                    self?.dismissFromUserAction()
                },
                onPinChange: { isPinned in
                    GrammarSettings.shared.isResultsPopupPinned = isPinned
                }
            )

            let hostingView = NSHostingView(rootView: view)
            hostingView.setFrameSize(hostingView.fittingSize)
            let contentSize = hostingView.fittingSize

            let origin = self.positionedOrigin(anchor: anchor, size: contentSize)

            let panel = GrammarClickablePanel(contentRect: NSRect(origin: origin, size: contentSize))
            panel.contentView = hostingView
            panel.orderFrontRegardless()
            panel.invalidateShadow()

            self.window = panel
            self.anchorPoint = nil
            self.installDismissMonitors()
            onPresented?()
        }
    }

    func dismiss() {
        removeMonitors()
        window?.orderOut(nil)
        window = nil
        resultsModel = nil
        onUserDismiss = nil
    }

    private func dismissFromUserAction() {
        let callback = onUserDismiss
        dismiss()
        callback?()
    }

    private func showStatus<V: View>(_ view: V, size: NSSize, at anchor: NSPoint) {
        let hostingView = NSHostingView(rootView: view)
        let frame = NSRect(origin: positionedOrigin(anchor: anchor, size: size), size: size)

        if let window {
            window.contentView = hostingView
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            return
        }

        let statusWindow = NSWindow(
            contentRect: frame,
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
            guard !GrammarSettings.shared.isResultsPopupPinned else { return }
            if !window.frame.contains(NSEvent.mouseLocation) {
                self.dismissFromUserAction()
            }
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismissFromUserAction()
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
    private var title: String { GrammarPopupCopy.current.improvingText }

    var body: some View {
        ProgressView()
            .controlSize(.regular)
            .tint(.accentColor)
            .frame(width: 32, height: 32)
            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
            .accessibilityLabel(title)
            .accessibilityIdentifier("grammar.status.loading")
    }
}

private struct GrammarStatusView: View {
    enum State: Equatable {
        case success
        case error
    }

    let state: State

    private var copy: GrammarPopupCopy { .current }

    private var title: String {
        switch state {
        case .success:
            return copy.appliedText
        case .error:
            return copy.errorText
        }
    }

    private var color: Color {
        switch state {
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var accessibilityIdentifier: String {
        switch state {
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

                if state == .success {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                } else {
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
    @ObservedObject var model: GrammarResultsModel
    let onSelect: (String) -> Void
    let onDismiss: () -> Void
    let onPinChange: (Bool) -> Void

    @State private var isPinned: Bool

    init(
        model: GrammarResultsModel,
        isPinned: Bool,
        onSelect: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void,
        onPinChange: @escaping (Bool) -> Void
    ) {
        self.model = model
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.onPinChange = onPinChange
        _isPinned = State(initialValue: isPinned)
    }

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
                    HStack(spacing: 6) {
                        if model.isStreaming {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityLabel(copy.improvingText)
                                .accessibilityIdentifier("grammar.results.streaming")
                        }

                        Text(copy.optionCount(model.response.options.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    isPinned.toggle()
                    onPinChange(isPinned)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                .background(isPinned ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                .clipShape(Circle())
                .help(isPinned ? copy.unpinLabel : copy.pinLabel)
                .accessibilityLabel(isPinned ? copy.unpinLabel : copy.pinLabel)
                .accessibilityValue(isPinned ? copy.pinnedLabel : copy.unpinnedLabel)
                .accessibilityIdentifier("grammar.results.pin")

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
                    if let errors = model.response.errors {
                        GrammarResultSection(
                            title: copy.errorsTitle,
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange,
                            text: errors
                        )
                    }

                    if !model.response.options.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(copy.chooseVersionTitle, systemImage: "text.badge.checkmark")
                                .font(.subheadline.weight(.semibold))
                                .symbolRenderingMode(.hierarchical)

                            ForEach(Array(model.response.options.enumerated()), id: \.offset) { index, option in
                                GrammarOptionButton(
                                    index: index + 1,
                                    title: copy.optionTitle(index + 1),
                                    text: option,
                                    isEnabled: !model.isStreaming,
                                    onSelect: onSelect
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        }
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
    let isEnabled: Bool
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
        .onHover { hovering in
            isHovered = hovering && isEnabled
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
    let errorsTitle: String
    let chooseVersionTitle: String
    let closeLabel: String
    let pinLabel: String
    let unpinLabel: String
    let pinnedLabel: String
    let unpinnedLabel: String
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
                errorsTitle: "What to fix",
                chooseVersionTitle: "Choose a version",
                closeLabel: "Close",
                pinLabel: "Keep on Screen",
                unpinLabel: "Unpin",
                pinnedLabel: "Pinned",
                unpinnedLabel: "Not pinned",
                optionLabel: "Option",
                optionsLabel: "options"
            )
        case .chinese:
            return GrammarPopupCopy(
                improvingText: "正在优化所选文本",
                appliedText: "文本已替换",
                errorText: "无法优化文本",
                resultsTitle: "写作建议",
                errorsTitle: "需要修改",
                chooseVersionTitle: "选择一个版本",
                closeLabel: "关闭",
                pinLabel: "固定在屏幕上",
                unpinLabel: "取消固定",
                pinnedLabel: "已固定",
                unpinnedLabel: "未固定",
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
