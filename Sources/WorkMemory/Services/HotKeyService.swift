import Carbon
import Foundation

final class HotKeyService: ObservableObject {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]

    deinit {
        unregister()
    }

    func registerShortcuts(
        quickCapture: @escaping () -> Void,
        globalDictation: @escaping () -> Void,
        instantOCR: @escaping () -> Void
    ) {
        unregister()
        handlers = [
            1: quickCapture,
            2: globalDictation,
            3: instantOCR
        ]

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()

            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            DispatchQueue.main.async {
                service.handlers[hotKeyID.id]?()
            }
            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        registerHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey),
            id: 1
        )

        registerHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey | shiftKey),
            id: 2
        )

        registerHotKey(
            keyCode: UInt32(kVK_ANSI_O),
            modifiers: UInt32(optionKey | cmdKey),
            id: 3
        )
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs = []

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        handlers = [:]
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x574D454D), id: id)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else { return }
        hotKeyRefs.append(hotKeyRef)
    }
}
