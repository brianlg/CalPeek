import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey registered via Carbon's `RegisterEventHotKey` — the
/// only way to get a global shortcut without requiring Accessibility access.
/// Deregisters itself when deallocated.
@MainActor
final class GlobalHotKey {
    private let handler: () -> Void
    /// Written once in `init`, read again only in the nonisolated `deinit`;
    /// the instance is owned by the main-actor `AppDelegate` for its lifetime.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?

    /// Four-char code "PEEK" namespacing our hotkey IDs.
    private static let signature: OSType = 0x5045_454B

    /// ⌥⌘J — join the next meeting.
    static func joinMeeting(handler: @escaping @MainActor () -> Void) -> GlobalHotKey? {
        GlobalHotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | optionKey), id: 1, handler: handler)
    }

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping @MainActor () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The C callback can't capture context, so `self` rides along as the
        // opaque userData pointer. Unretained is safe: `deinit` removes the
        // handler before the instance goes away.
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Application-target Carbon events are delivered on the main thread.
                MainActor.assumeIsolated { hotKey.handler() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr, hotKeyRef != nil else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
