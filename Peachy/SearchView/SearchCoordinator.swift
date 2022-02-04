import Carbon
import Cocoa
import Combine
import Foundation

final class SearchCoordinator {
    @Published private var keyword: String?
    @Published private var frontmostApp: NSRunningApplication?

    private let searchWindowController: SearchWindowController
    private let preferences: AppPreferences
    private var keywordSubscription: AnyCancellable?

    init(preferences: AppPreferences) {
        self.searchWindowController = .init()
        self.preferences = preferences
        searchWindowController.selectionDelegate = self
        searchWindowController.keyEventDelegate = self
        (searchWindowController.window as? SearchPanel)?.searchDelegate = self
        setupKeyListener()
        observeFrontmostApp()
        observeKeyword()
    }
}

// MARK: - Key Events
//
extension SearchCoordinator: KeyEventDelegate {
    func handleEvent(_ event: NSEvent) {
        if let char = event.characters,
           "a"..."z" ~= char {
            simulateKeyEvent(event)
            return
        }

        switch Int(event.keyCode) {
        case kVK_Delete:
            simulateKeyEvent(event)
        default:
            hideSearchWindow()
        }
    }
}

// MARK: - Global key event
//
private extension SearchCoordinator {
    func setupKeyListener() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            self.handleGlobalEvent(event)
        }
    }

    func handleGlobalEvent(_ event: NSEvent) {
        guard AppState.current.hasAXPermission,
              let id = frontmostApp?.bundleIdentifier,
              preferences.appExceptions[id] == nil else {
            return
        }
        let chars = event.characters?.lowercased()
        switch chars {
        case .some(preferences.triggerKey):
            keyword = ""
        case .some("a"..."z"):
            guard let key = keyword else {
                return
            }
            keyword = key + (chars ?? "")
        default:
            break
        }
        
        switch Int(event.keyCode) {
        case kVK_Delete:
            guard let key = keyword, !key.isEmpty else {
                return
            }
            if key.count == 1 {
                hideSearchWindow()
            } else {
                keyword = String(key.prefix(key.count-1))
            }
        case kVK_Escape:
            hideSearchWindow()
        default:
            break
        }
    }
}

// MARK: - SearchPanelDelegate conformance
//
extension SearchCoordinator: SearchPanelDelegate {
    func dismissPanel() {
        hideSearchWindow()
    }
}

// MARK: - ItemSelectionDelegate conformance
//
extension SearchCoordinator: ItemSelectionDelegate {
    func handleSelection(_ item: Kaomoji) {
        guard let keyword = keyword else { return }
        searchWindowController.window?.resignKey()
        replace(keyword: keyword, with: item.string)
        hideSearchWindow()
    }
}

// MARK: - Search window
//
private extension SearchCoordinator {
    /// Dismisses search if other app is activated
    ///
    func observeFrontmostApp() {
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.hideSearchWindow()
            })
            .assign(to: &$frontmostApp)
    }

    /// Filters kaomoji list and show drop down.
    ///
    func observeKeyword() {
        keywordSubscription = $keyword
            .compactMap { $0 }
            .sink { [weak self] word in
                guard !word.isEmpty else {
                    return
                }
                self?.reloadSearchWindow()
                self?.searchWindowController.query = word
            }
    }

    /// Dismisses search and resets keyword
    ///
    func hideSearchWindow() {
        keyword = nil
        searchWindowController.window?.orderOut(nil)
    }

    /// Places the search window where the text field in focus is.
    ///
    func reloadSearchWindow() {
        guard let app = frontmostApp else {
            return
        }

        if searchWindowController.window?.isVisible == false {
            var frameOrigin = NSPoint(x: NSScreen.main!.frame.size.width / 2 - 100, y: NSScreen.main!.frame.size.height / 2 - 100)
            if let frame = getTextSelectionBounds(for: app), frame.size != .zero {
                var yPosition = NSScreen.main!.frame.size.height - frame.origin.y - frame.size.height - 200
                if yPosition < 0 {
                    yPosition = NSScreen.main!.frame.size.height - frame.origin.y
                }
                frameOrigin = NSPoint(x: frame.origin.x + frame.size.width / 2, y: yPosition)
            } else if let frame = getFocusedElementFrame(for: app), frame.size != .zero {
                var yPosition = NSScreen.main!.frame.size.height - frame.origin.y - frame.size.height - 200
                if yPosition < 0 {
                    yPosition = NSScreen.main!.frame.size.height - frame.origin.y
                }
                frameOrigin = NSPoint(x: frame.origin.x, y: yPosition)
            }
            searchWindowController.frameOrigin = frameOrigin
            searchWindowController.showWindow(self)
        }
    }
}

// MARK: - Simulate Events
//
private extension SearchCoordinator {

    /// Simulates key event to the frontmost app
    ///
    func simulateKeyEvent(_ event: NSEvent) {
        searchWindowController.window?.resignKey()

        // simulate key down event
        let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: event.keyCode, keyDown: true)
        keyDownEvent?.post(tap: CGEventTapLocation.cghidEventTap)
    
        searchWindowController.window?.makeKey()
    }

    /// Uses System Events to keystroke and replace text with kaomoji.
    ///
    func replace(keyword: String, with kaomoji: String) {
        searchWindowController.window?.resignKey()
        let source = """
            tell application "System Events"
                repeat \(keyword.count + 1) times
                    key code 123 using {shift down}
                end repeat
                set the clipboard to "\(kaomoji)"
                keystroke "v" using command down
                delay 0.2
                set the clipboard to ""
            end tell
        """
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error = error {
                #if DEBUG
                print(error)
                #endif
            }
        }
    }
}

// MARK: - AX
//
private extension SearchCoordinator {

    /// Gets the front most app's focused element,
    /// retrieve selected range and return the bound.
    func getTextSelectionBounds(for app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
                == .success else {
                    return nil
                }
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success else {
            return nil
        }
        var selectedRange: CFRange = .init(location: 0, length: 0)
        AXValueGetValue(selectedRangeValue as! AXValue, AXValueType.cfRange, &selectedRange)
        var selectionBoundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focusedElement as! AXUIElement, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue as! AXValue, &selectionBoundsValue) == .success else {
            return nil
        }
        var selectionBounds: CGRect = .zero
        AXValueGetValue(selectionBoundsValue as! AXValue, AXValueType.cgRect, &selectionBounds)
        return selectionBounds
    }

    /// Gets the front most app's focused element,
    /// retrieve element's frame.
    func getFocusedElementFrame(for app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused element if any
        var focusedElement: CFTypeRef?
        guard
          AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            == .success else {
            return nil
        }

        // Make sure that the focused element is a text field or
        // a text view before moving on to calculating the position.
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXRoleAttribute as CFString, &roleValue) == .success else {
            return nil
        }
        if (roleValue as? String) != kAXTextFieldRole &&
            (roleValue as? String) != kAXTextAreaRole {
            return nil
        }

        // Calculate the position of the element
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXPositionAttribute as CFString, &positionValue) == .success else {
            return nil
        }
        var position: CGPoint = .zero
        AXValueGetValue(positionValue as! AXValue, AXValueType.cgPoint, &position)

        // Calculate the size of the element
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }
        var size: CGSize = .zero
        AXValueGetValue(sizeValue as! AXValue, AXValueType.cgSize, &size)

        return CGRect(origin: position, size: size)
    }
}
