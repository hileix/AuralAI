//
//  TranslationFloatingIndicator.swift
//  AuralAI
//

import AppKit
import SwiftUI

private final class TranslationPanel: NSPanel {
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

final class TranslationFloatingIndicator {
    static let shared = TranslationFloatingIndicator()

    private let statusSize = NSSize(width: 268, height: 60)
    private var window: NSWindow?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var anchorPoint: NSPoint?
    private var onUserDismiss: (() -> Void)?
    private var scheduledDismissID: UUID?

    private init() {}

    func showLoading(at anchor: NSPoint) {
        DispatchQueue.main.async {
            self.dismiss()
            self.anchorPoint = anchor
            self.showStatus(TranslationLoadingView(), size: NSSize(width: 32, height: 32), at: anchor)
        }
    }

    func showError(at anchor: NSPoint?) {
        DispatchQueue.main.async {
            self.showStatus(
                TranslationErrorView(),
                size: self.statusSize,
                at: anchor ?? self.anchorPoint ?? NSEvent.mouseLocation
            )
            self.dismissAfterDelay()
        }
    }

    func showResults(
        result: TranslationResult,
        at previewAnchor: NSPoint?,
        onUserDismiss: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            self.dismiss()

            let anchor = previewAnchor ?? self.anchorPoint ?? NSEvent.mouseLocation
            self.onUserDismiss = onUserDismiss
            let view = TranslationResultsView(
                result: result,
                isPinned: TranslationSettings.shared.isResultsPopupPinned,
                onDismiss: { [weak self] in self?.dismissFromUserAction() },
                onPinChange: { isPinned in
                    TranslationSettings.shared.isResultsPopupPinned = isPinned
                }
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.setFrameSize(hostingView.fittingSize)
            let contentSize = hostingView.fittingSize
            let origin = self.positionedOrigin(anchor: anchor, size: contentSize)
            let panel = TranslationPanel(contentRect: NSRect(origin: origin, size: contentSize))
            panel.contentView = hostingView
            panel.orderFrontRegardless()
            panel.invalidateShadow()

            self.window = panel
            self.anchorPoint = nil
            self.installDismissMonitors()
        }
    }

    func dismiss() {
        scheduledDismissID = nil
        removeMonitors()
        window?.orderOut(nil)
        window = nil
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
        let dismissID = UUID()
        scheduledDismissID = dismissID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.scheduledDismissID == dismissID else { return }
            self.scheduledDismissID = nil
            self.dismiss()
        }
    }

    private func installDismissMonitors() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let window = self.window else { return }
            guard !TranslationSettings.shared.isResultsPopupPinned else { return }
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
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }
}

private struct TranslationLoadingView: View {
    @State private var loadingPhase: CGFloat = 0

    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.42), .clear],
                    startPoint: UnitPoint(x: loadingPhase - 0.62, y: 0.15),
                    endPoint: UnitPoint(x: loadingPhase - 0.08, y: 0.85)
                )
                .blendMode(.screen)
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
            .accessibilityLabel(TranslationCopy.current.translatingText)
            .accessibilityIdentifier("translation.status.loading")
            .onAppear {
                loadingPhase = 1
            }
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: loadingPhase)
    }
}

private struct TranslationErrorView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(TranslationCopy.current.errorText)
                .font(.system(size: 14, weight: .semibold))
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
        .accessibilityIdentifier("translation.status.error")
    }
}

private struct TranslationResultsView: View {
    let result: TranslationResult
    let onDismiss: () -> Void
    let onPinChange: (Bool) -> Void

    @State private var isPinned: Bool

    init(
        result: TranslationResult,
        isPinned: Bool,
        onDismiss: @escaping () -> Void,
        onPinChange: @escaping (Bool) -> Void
    ) {
        self.result = result
        self.onDismiss = onDismiss
        self.onPinChange = onPinChange
        _isPinned = State(initialValue: isPinned)
    }

    private var copy: TranslationCopy { .current }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(copy.resultsTitle)
                    .font(.headline)
                    .accessibilityIdentifier("translation.results")
                Spacer()
                Button {
                    isPinned.toggle()
                    onPinChange(isPinned)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                .background(isPinned ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                .clipShape(Circle())
                .help(isPinned ? copy.unpinLabel : copy.pinLabel)
                .accessibilityLabel(isPinned ? copy.unpinLabel : copy.pinLabel)
                .accessibilityIdentifier("translation.results.pin")
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
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
                VStack(alignment: .leading, spacing: 18) {
                    TranslationTextSection(title: copy.originalTitle, text: result.originalText, color: .secondary)
                    TranslationTextSection(title: copy.translationTitle, text: result.translatedText, color: .blue)
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct TranslationTextSection: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TranslationCopy {
    let translatingText: String
    let errorText: String
    let resultsTitle: String
    let originalTitle: String
    let translationTitle: String
    let closeLabel: String
    let pinLabel: String
    let unpinLabel: String

    static var current: TranslationCopy {
        switch SpeechSettings.shared.language {
        case .english:
            return TranslationCopy(
                translatingText: "Translating selected text",
                errorText: "Couldn't translate text",
                resultsTitle: "Translation",
                originalTitle: "Original text",
                translationTitle: "Translation",
                closeLabel: "Close",
                pinLabel: "Keep on Screen",
                unpinLabel: "Unpin"
            )
        case .chinese:
            return TranslationCopy(
                translatingText: "正在翻译所选文本",
                errorText: "无法翻译文本",
                resultsTitle: "翻译",
                originalTitle: "原始文本",
                translationTitle: "翻译结果",
                closeLabel: "关闭",
                pinLabel: "固定在屏幕上",
                unpinLabel: "取消固定"
            )
        }
    }
}
