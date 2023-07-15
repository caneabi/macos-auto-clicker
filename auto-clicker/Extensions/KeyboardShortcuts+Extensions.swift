//
//  KeyboardShortcuts+Extensions.swift
//  auto-clicker
//
//  Created by Ben Tindall on 17/07/2022.
//

import Foundation
import KeyboardShortcuts
import SwiftUI
import Carbon

extension KeyboardShortcuts.Shortcut {
    /**
    The string representation of the keyboard shortcut key only.

    ```
    print(Shortcut(.a, modifiers: [.command]))
    //=> "A"
    ```
    */
    public var descriptionKeyOnly: String {
        // 'keyToCharacter' is inaccessible due to 'fileprivate' protection level
        // :(
//        modifiers.description + (keyToCharacter()?.uppercased() ?? "�")

        // Hacky due to the above fileprivate protection level of keyToCharacter()
        // So just strip the modifier from the string to gain access to a string representation of just the key alone
        self.description.replacingOccurrences(of: modifiers.description, with: "")
    }

    // https://github.com/sindresorhus/KeyboardShortcuts/issues/101#issuecomment-1325196892
    func toKeyEquivalent() -> KeyEquivalent? {
        let carbonKeyCode = UInt16(self.carbonKeyCode)
        let maxNameLength = 4
        var nameBuffer = [UniChar](repeating: 0, count: maxNameLength)
        var nameLength = 0

        let modifierKeys = UInt32(alphaLock >> 8) & 0xFF // Caps Lock
        var deadKeys: UInt32 = 0
        let keyboardType = UInt32(LMGetKbdType())

        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            NSLog("Could not get keyboard layout data")
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        let osStatus = layoutData.withUnsafeBytes {
            UCKeyTranslate($0.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                           carbonKeyCode,
                           UInt16(kUCKeyActionDown),
                           modifierKeys,
                           keyboardType,
                           UInt32(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeys,
                           maxNameLength,
                           &nameLength,
                           &nameBuffer)
        }
        guard osStatus == noErr else {
            NSLog("Code: 0x%04X  Status: %+i", carbonKeyCode, osStatus)
            return nil
        }

        return KeyEquivalent(Character(String(utf16CodeUnits: nameBuffer, count: nameLength)))
    }

    // https://github.com/sindresorhus/KeyboardShortcuts/issues/101#issuecomment-1325196892
    func toEventModifiers() -> SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []

        if self.modifiers.contains(NSEvent.ModifierFlags.command) {
            modifiers.update(with: EventModifiers.command)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.control) {
            modifiers.update(with: EventModifiers.control)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.option) {
            modifiers.update(with: EventModifiers.option)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.shift) {
            modifiers.update(with: EventModifiers.shift)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.capsLock) {
            modifiers.update(with: EventModifiers.capsLock)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.numericPad) {
            modifiers.update(with: EventModifiers.numericPad)
        }

        return modifiers
    }
}
