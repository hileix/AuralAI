//
//  FocusedTextInputService.swift
//  AuralAI
//

import AppKit
import ApplicationServices
import OSLog

struct FocusedTextInput {
    let element: AXUIElement
    let frame: NSRect
    let processIdentifier: pid_t
    let hasContent: Bool
    let selectedText: String?
    let selectedRange: CFRange?

    var hasSelection: Bool {
        selectedText != nil
    }

    var anchorPoint: NSPoint {
        NSPoint(x: frame.maxX - 18, y: frame.maxY - 18)
    }
}

struct FocusedTextSelection {
    let text: String
    let range: CFRange?
}

final class FocusedTextInputService {
    static let shared = FocusedTextInputService()

    private var systemWideElement = AXUIElementCreateSystemWide()
    private let logger = Logger(subsystem: "com.xiaolei.AuralAI", category: "FocusedTextInput")
    private var refreshTimer: Timer?
    private var isPaused = false

    private var lastDiagnostic = ""
    private var currentExternalSelectionElement: AXUIElement?
    private var currentExternalSelection: FocusedTextSelection?

    private(set) var currentInput: FocusedTextInput?
    var onFocusedInputChange: ((FocusedTextInput?) -> Void)?
    var onExternalSelectionChange: ((FocusedTextSelection?) -> Void)?

    var hasExternalSelection: Bool {
        currentExternalSelection != nil
    }

    private init() {}

    func start() {
        guard refreshTimer == nil else { return }

        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refreshAccessibilityContext() {
        systemWideElement = AXUIElementCreateSystemWide()
        lastDiagnostic = ""
        refresh()
    }

    func captureCurrentInput() -> FocusedTextInput? {
        guard !isPaused else { return nil }
        refresh()
        return currentInput
    }

    func pause() {
        isPaused = true
    }

    func resume(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.isPaused = false
            self.refresh()
        }
    }

    func readText(from input: FocusedTextInput) -> String? {
        if let value = copyAttribute(kAXValueAttribute, from: input.element) {
            if let text = value as? String {
                logger.notice("Read focused text using AXValue length=\(text.count)")
                return text
            }
            if let attributedText = value as? NSAttributedString {
                logger.notice("Read focused text using attributed AXValue length=\(attributedText.length)")
                return attributedText.string
            }
            logger.notice("Focused input AXValue has unsupported type id=\(CFGetTypeID(value))")
        }

        guard let countValue = copyAttribute(kAXNumberOfCharactersAttribute, from: input.element),
              let count = countValue as? Int,
              count >= 0 else {
            return nil
        }

        var range = CFRange(location: 0, length: count)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }

        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            input.element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &result
        )

        guard error == .success else {
            logger.error("AXStringForRange failed with error=\(error.rawValue)")
            return nil
        }
        guard let text = result as? String else {
            logger.error("AXStringForRange returned a non-string value")
            return nil
        }
        logger.notice("Read focused text using AXStringForRange length=\(text.count)")
        return text
    }

    func readSelection(from input: FocusedTextInput) -> FocusedTextSelection? {
        readSelection(from: input.element)
    }

    private func readSelection(from element: AXUIElement) -> FocusedTextSelection? {
        var selectedRange: CFRange?
        if let value = copyAttribute(kAXSelectedTextRangeAttribute, from: element),
           CFGetTypeID(value) == AXValueGetTypeID() {
            let rangeValue = value as! AXValue
            var range = CFRange()
            if AXValueGetType(rangeValue) == .cfRange,
               AXValueGetValue(rangeValue, .cfRange, &range),
               range.length > 0 {
                selectedRange = range
            }
        }

        if let value = copyAttribute(kAXSelectedTextAttribute, from: element) {
            if let text = value as? String, Self.hasMeaningfulContent(text) {
                logger.notice("Read selected text using AXSelectedText length=\(text.count)")
                return FocusedTextSelection(text: text, range: selectedRange)
            }
            if let attributedText = value as? NSAttributedString,
               Self.hasMeaningfulContent(attributedText.string) {
                logger.notice("Read selected text using attributed AXSelectedText length=\(attributedText.length)")
                return FocusedTextSelection(text: attributedText.string, range: selectedRange)
            }
        }

        if let markerSelection = readTextMarkerSelection(from: element) {
            return markerSelection
        }

        guard var range = selectedRange,
              let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &result
        )
        guard error == .success,
              let text = result as? String,
              Self.hasMeaningfulContent(text) else {
            logger.error("Could not read selected text for range length=\(range.length)")
            return nil
        }

        logger.notice("Read selected text using AXStringForRange length=\(text.count)")
        return FocusedTextSelection(text: text, range: range)
    }

    private func readTextMarkerSelection(from element: AXUIElement) -> FocusedTextSelection? {
        guard let markerRange = copyAttribute("AXSelectedTextMarkerRange", from: element) else {
            return nil
        }

        var result: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRange,
            &result
        )
        guard error == .success else { return nil }

        if let text = result as? String, Self.hasMeaningfulContent(text) {
            logger.notice("Read selected text using AX text markers length=\(text.count)")
            return FocusedTextSelection(text: text, range: nil)
        }
        if let attributedText = result as? NSAttributedString,
           Self.hasMeaningfulContent(attributedText.string) {
            logger.notice("Read selected text using attributed AX text markers length=\(attributedText.length)")
            return FocusedTextSelection(text: attributedText.string, range: nil)
        }

        return nil
    }

    func restoreSelection(_ selection: FocusedTextSelection, in input: FocusedTextInput) -> Bool {
        if var range = selection.range,
           let rangeValue = AXValueCreate(.cfRange, &range),
           AXUIElementSetAttributeValue(
               input.element,
               kAXSelectedTextRangeAttribute as CFString,
               rangeValue
           ) == .success {
            return true
        }

        return readSelection(from: input)?.text == selection.text
    }

    @discardableResult
    func focus(_ input: FocusedTextInput) -> Bool {
        AXUIElementSetAttributeValue(
            input.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }

    private func refresh() {
        guard !isPaused else { return }

        guard AXIsProcessTrusted() else {
            logDiagnostic("Accessibility permission is not granted")
            publish(nil)
            publishExternalSelection(nil, element: nil)
            return
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            publish(nil)
            publishExternalSelection(nil, element: nil)
            return
        }

        guard let focusedElement = focusedElement() else {
            logDiagnostic("No focused Accessibility element")
            publish(nil)
            publishExternalSelection(nil, element: nil)
            return
        }

        guard let textElement = supportedTextElement(startingAt: focusedElement) else {
            logDiagnostic("Unsupported focus chain: \(roleChain(startingAt: focusedElement))")
            publish(nil)
            let externalSelection = externalSelection(startingAt: focusedElement)
            publishExternalSelection(externalSelection?.selection, element: externalSelection?.element)
            return
        }

        guard let input = makeInput(from: textElement) else {
            logDiagnostic("Supported text element has no usable frame: \(roleChain(startingAt: textElement))")
            publish(nil)
            publishExternalSelection(nil, element: nil)
            return
        }

        logDiagnostic("Detected text input pid=\(input.processIdentifier) frame=\(NSStringFromRect(input.frame))")
        publishExternalSelection(nil, element: nil)
        publish(input)
    }

    private func focusedElement() -> AXUIElement? {
        guard let value = copyAttribute(kAXFocusedUIElementAttribute, from: systemWideElement),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func supportedTextElement(startingAt element: AXUIElement) -> AXUIElement? {
        var candidate = element

        for _ in 0..<6 {
            if isSupportedTextElement(candidate) {
                return candidate
            }

            guard let parentValue = copyAttribute(kAXParentAttribute, from: candidate),
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                return nil
            }
            candidate = parentValue as! AXUIElement
        }

        return nil
    }

    private func externalSelection(
        startingAt focusedElement: AXUIElement
    ) -> (element: AXUIElement, selection: FocusedTextSelection)? {
        var startingElements: [AXUIElement] = []
        if let mouseElement = elementAtMousePosition() {
            startingElements.append(mouseElement)
        }
        if !startingElements.contains(where: { CFEqual($0, focusedElement) }) {
            startingElements.append(focusedElement)
        }

        for startingElement in startingElements {
            var candidate = startingElement

            for _ in 0..<10 {
                if let selection = readSelection(from: candidate) {
                    return (candidate, selection)
                }

                guard let parentValue = copyAttribute(kAXParentAttribute, from: candidate),
                      CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                    break
                }
                candidate = parentValue as! AXUIElement
            }
        }

        return nil
    }

    private func elementAtMousePosition() -> AXUIElement? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }

        let mouseLocation = NSEvent.mouseLocation
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(mouseLocation.x),
            Float(primaryScreen.frame.maxY - mouseLocation.y),
            &element
        )
        guard error == .success else { return nil }
        return element
    }

    private func isSupportedTextElement(_ element: AXUIElement) -> Bool {
        guard let role = copyAttribute(kAXRoleAttribute, from: element) as? String,
              role == kAXTextFieldRole as String
                || role == kAXTextAreaRole as String
                || role == kAXComboBoxRole as String else {
            return false
        }

        if let subrole = copyAttribute(kAXSubroleAttribute, from: element) as? String,
           subrole == kAXSecureTextFieldSubrole as String {
            return false
        }

        if let enabled = copyAttribute(kAXEnabledAttribute, from: element) as? Bool,
           !enabled {
            return false
        }

        return true
    }

    private func makeInput(from element: AXUIElement) -> FocusedTextInput? {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: element),
              let sizeValue = copyAttribute(kAXSizeAttribute, from: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        let axPositionValue = positionValue as! AXValue
        let axSizeValue = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetType(axPositionValue) == .cgPoint,
              AXValueGetType(axSizeValue) == .cgSize,
              AXValueGetValue(axPositionValue, .cgPoint, &position),
              AXValueGetValue(axSizeValue, .cgSize, &size),
              size.width >= 40,
              size.height >= 20,
              let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        let frame = Self.appKitFrame(
            position: position,
            size: size,
            primaryScreenMaxY: primaryScreen.frame.maxY
        )
        guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }

        let selection = readSelection(from: element)

        return FocusedTextInput(
            element: element,
            frame: frame,
            processIdentifier: pid,
            hasContent: inputContainsText(element) ?? true,
            selectedText: selection?.text,
            selectedRange: selection?.range
        )
    }

    private func inputContainsText(_ element: AXUIElement) -> Bool? {
        if let value = copyAttribute(kAXValueAttribute, from: element) {
            if let text = value as? String {
                return Self.hasMeaningfulContent(text)
            }
            if let attributedText = value as? NSAttributedString {
                return Self.hasMeaningfulContent(attributedText.string)
            }
        }

        if let count = copyAttribute(kAXNumberOfCharactersAttribute, from: element) as? Int {
            return count > 0
        }

        return nil
    }

    static func hasMeaningfulContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func appKitFrame(
        position: CGPoint,
        size: CGSize,
        primaryScreenMaxY: CGFloat
    ) -> NSRect {
        NSRect(
            x: position.x,
            y: primaryScreenMaxY - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func roleChain(startingAt element: AXUIElement) -> String {
        var parts: [String] = []
        var candidate = element

        for _ in 0..<6 {
            let role = copyAttribute(kAXRoleAttribute, from: candidate) as? String ?? "unknown"
            let subrole = copyAttribute(kAXSubroleAttribute, from: candidate) as? String
            parts.append(subrole.map { "\(role)[\($0)]" } ?? role)

            guard let parentValue = copyAttribute(kAXParentAttribute, from: candidate),
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            candidate = parentValue as! AXUIElement
        }

        return parts.joined(separator: " > ")
    }

    private func logDiagnostic(_ message: String) {
        guard message != lastDiagnostic else { return }
        lastDiagnostic = message
        logger.notice("\(message, privacy: .public)")
        print("[FocusedTextInput] \(message)")
    }

    private func publish(_ input: FocusedTextInput?) {
        if let currentInput, let input,
           CFEqual(currentInput.element, input.element),
           currentInput.frame.equalTo(input.frame),
           currentInput.hasContent == input.hasContent,
           currentInput.selectedText == input.selectedText,
           rangesEqual(currentInput.selectedRange, input.selectedRange) {
            return
        }

        if currentInput == nil, input == nil {
            return
        }

        currentInput = input
        onFocusedInputChange?(input)
    }

    private func publishExternalSelection(
        _ selection: FocusedTextSelection?,
        element: AXUIElement?
    ) {
        if let currentExternalSelection, let selection,
           let currentExternalSelectionElement, let element,
           CFEqual(currentExternalSelectionElement, element),
           currentExternalSelection.text == selection.text,
           rangesEqual(currentExternalSelection.range, selection.range) {
            return
        }

        if currentExternalSelection == nil, selection == nil {
            return
        }

        currentExternalSelectionElement = element
        currentExternalSelection = selection
        onExternalSelectionChange?(selection)
    }

    private func rangesEqual(_ lhs: CFRange?, _ rhs: CFRange?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (.some(lhs), .some(rhs)):
            return lhs.location == rhs.location && lhs.length == rhs.length
        default:
            return false
        }
    }
}
