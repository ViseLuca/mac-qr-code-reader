import Carbon.HIToolbox

/// System-wide hotkeys via Carbon `RegisterEventHotKey` (no Accessibility permission needed).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false
    private let signature: OSType = 0x5152_5244 // 'QRRD'

    /// False if macOS refuses the combination, usually because another app has already registered it.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        handlers[id] = handler
        refs.append(ref)
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        handlers = [:]
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id: hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
