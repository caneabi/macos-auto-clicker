//
//  AutoClickSimulator.swift
//  auto-clicker
//
//  Created by Ben Tindall on 12/05/2021.
//

import Foundation
import Combine
import SwiftUI
import Defaults
import UserNotifications

final class AutoClickSimulator: ObservableObject {
    static var shared: AutoClickSimulator = .init()
    private init() {}

    @Published var isAutoClicking = false

    @Published var remainingInterations: Int = 0

    @Published var nextClickAt: Date = .init()
    @Published var finalClickAt: Date = .init()

    // Said weird behaviour is still occuring in 12.2.1, thus having these defined in here instead of Published, I hate this though so much
    private var duration: Duration = .milliseconds
    private var interval: Int = DEFAULT_PRESS_INTERVAL
    private var amountOfPresses: Int = DEFAULT_REPEAT_AMOUNT
    private var input = Input()

    private var timer: Timer?
    private var mouseLocation: NSPoint { NSEvent.mouseLocation }
    private var activity: Cancellable?

    private var monitorObject: Any?
    private var startMonitorObject: Any?
    private var initialMousePosition: NSPoint?
    private var mouseDeltaThreshold: CGFloat = 0.0

    func start() {
        self.isAutoClicking = true

        // Stop mouse start monitoring if it's running
        self.stopMouseStartMonitoring()

        if let startMenuItem = MenuBarService.startMenuItem {
            startMenuItem.isEnabled = false
        }

        if let stopMenuItem = MenuBarService.stopMenuItem {
            stopMenuItem.isEnabled = true
        }

        MenuBarService.changeImageColour(newColor: .systemBlue)

        self.activity = ProcessInfo.processInfo.beginActivity(.autoClicking)

        self.duration = Defaults[.autoClickerState].pressIntervalDuration
        let intervalMode = Defaults[.autoClickerState].intervalMode
        if intervalMode == .rangeInterval {
            let min = Defaults[.autoClickerState].pressIntervalMin ?? DEFAULT_PRESS_INTERVAL_MIN
            let max = Defaults[.autoClickerState].pressIntervalMax ?? DEFAULT_PRESS_INTERVAL_MAX
            self.interval = Int.random(in: min...max)
        } else {
            self.interval = Defaults[.autoClickerState].pressInterval
        }
        self.input = Defaults[.autoClickerState].pressInput
        self.amountOfPresses = Defaults[.autoClickerState].pressAmount
        self.remainingInterations = Defaults[.autoClickerState].repeatAmount

        self.finalClickAt = .init(timeInterval: self.duration.asTimeInterval(interval: self.interval * self.remainingInterations), since: .init())

        let timeInterval = self.duration.asTimeInterval(interval: self.interval)
        self.nextClickAt = .init(timeInterval: timeInterval, since: .init())
        self.timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                          target: self,
                                          selector: #selector(self.tick),
                                          userInfo: nil,
                                          repeats: true)

        if Defaults[.mouseStopOnMove] {
            self.initialMousePosition = nil
            self.mouseDeltaThreshold = CGFloat(Defaults[.mouseDeltaThreshold])
            startMouseMonitoring()
        }

        if Defaults[.notifyOnStart] {
            NotificationService.scheduleNotification(title: "Started", date: self.nextClickAt)
        }

        if Defaults[.notifyOnFinish] {
            NotificationService.scheduleNotification(title: "Finished", date: self.finalClickAt)
        }
    }

    func stop(triggeredByMouseMovement: Bool = false) {
        self.isAutoClicking = false

        if let monitorObject = self.monitorObject {
            NSEvent.removeMonitor(monitorObject)
            self.monitorObject = nil
        }

        if let startMenuItem = MenuBarService.startMenuItem {
            startMenuItem.isEnabled = true
        }

        if let stopMenuItem = MenuBarService.stopMenuItem {
            stopMenuItem.isEnabled = false
        }

        MenuBarService.resetImage()

        self.activity?.cancel()
        self.activity = nil

        // Force zero, as the user could stop the timer early
        self.remainingInterations = 0

        if let timer = self.timer {
            timer.invalidate()
        }

        if triggeredByMouseMovement {
            NotificationService.removePendingNotifications()

            if Defaults[.notifyOnFinish] {
                NotificationService.scheduleNotification(title: "Finished", date: Date())
            }
        } else {
            NotificationService.removePendingNotifications()
        }

        // Re-enable mouse start monitoring if it was enabled
        if Defaults[.mouseStartOnMove] && !self.isAutoClicking {
            self.startMouseStartMonitoring()
        }
    }

    func startMouseStartMonitoring() {
        // Stop any existing monitoring
        if let startMonitorObject = self.startMonitorObject {
            NSEvent.removeMonitor(startMonitorObject)
            self.startMonitorObject = nil
        }

        self.initialMousePosition = nil
        self.mouseDeltaThreshold = CGFloat(Defaults[.mouseDeltaThreshold])

        self.startMonitorObject = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.mouseMovedForStart(event)
        }
    }

    func stopMouseStartMonitoring() {
        if let startMonitorObject = self.startMonitorObject {
            NSEvent.removeMonitor(startMonitorObject)
            self.startMonitorObject = nil
        }
    }

    @objc private func tick() {
        self.remainingInterations -= 1

        self.press()

        // Update interval if in range mode
        let intervalMode = Defaults[.autoClickerState].intervalMode
        if intervalMode == .rangeInterval {
            let min = Defaults[.autoClickerState].pressIntervalMin ?? DEFAULT_PRESS_INTERVAL_MIN
            let max = Defaults[.autoClickerState].pressIntervalMax ?? DEFAULT_PRESS_INTERVAL_MAX
            self.interval = Int.random(in: min...max)
        } else {
            self.interval = Defaults[.autoClickerState].pressInterval
        }

        self.nextClickAt = .init(timeInterval: self.duration.asTimeInterval(interval: self.interval), since: .init())

        if self.remainingInterations <= 0 {
            self.stop()
        }
    }

    private func startMouseMonitoring() {
        self.monitorObject = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.mouseMoved(event)
        }
    }

    private func mouseMoved(_ event: NSEvent) {
        let position = event.locationInWindow
        if let initialPosition = self.initialMousePosition {
            let deltaX = position.x - initialPosition.x
            let deltaY = position.y - initialPosition.y
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
            if distance > mouseDeltaThreshold {
                self.stop(triggeredByMouseMovement: true)
            }
        } else {
            self.initialMousePosition = position
        }
    }

    private func mouseMovedForStart(_ event: NSEvent) {
        let position = event.locationInWindow
        if let initialPosition = self.initialMousePosition {
            let deltaX = position.x - initialPosition.x
            let deltaY = position.y - initialPosition.y
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
            if distance > mouseDeltaThreshold {
                // Stop monitoring and start the auto clicker
                self.stopMouseStartMonitoring()
                self.start()
            }
        } else {
            self.initialMousePosition = position
        }
    }

    private let mouseDownEventMap: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseDown,
        .leftMouseUp: .leftMouseDown,
        .rightMouseDown: .rightMouseDown,
        .rightMouseUp: .rightMouseDown,
        .otherMouseDown: .otherMouseDown,
        .otherMouseUp: .otherMouseDown
    ]

    private let mouseUpEventMap: [NSEvent.EventType: CGEventType] = [
        .leftMouseDown: .leftMouseUp,
        .leftMouseUp: .leftMouseUp,
        .rightMouseDown: .rightMouseUp,
        .rightMouseUp: .rightMouseUp,
        .otherMouseDown: .otherMouseUp,
        .otherMouseUp: .otherMouseUp
    ]

    private let mouseButtonEventMap: [NSEvent.EventType: CGMouseButton] = [
        .leftMouseDown: .left,
        .leftMouseUp: .left,
        .rightMouseDown: .right,
        .rightMouseUp: .right,
        .otherMouseDown: .center,
        .otherMouseUp: .center
    ]

    private func generateMouseClickEvents(source: CGEventSource?) -> [CGEvent?] {
        let mouseX = self.mouseLocation.x
        let mouseY = NSScreen.screens[0].frame.height - mouseLocation.y

        let clickingAtPoint = CGPoint(x: mouseX, y: mouseY)

        let mouseDownType: CGEventType = mouseDownEventMap[self.input.type]!
        let mouseUpType: CGEventType = mouseUpEventMap[self.input.type]!
        let mouseButton: CGMouseButton = mouseButtonEventMap[self.input.type]!

        let mouseDown = CGEvent(mouseEventSource: source,
                                mouseType: mouseDownType,
                                mouseCursorPosition: clickingAtPoint,
                                mouseButton: mouseButton)

        let mouseUp = CGEvent(mouseEventSource: source,
                              mouseType: mouseUpType,
                              mouseCursorPosition: clickingAtPoint,
                              mouseButton: mouseButton)

        return [mouseDown, mouseUp]
    }

    private func generateKeyPressEvents(source: CGEventSource?) -> [CGEvent?] {
        let keyDown = CGEvent(keyboardEventSource: source,
                              virtualKey: CGKeyCode(self.input.keyCode),
                              keyDown: true)

        let keyUp = CGEvent(keyboardEventSource: source,
                            virtualKey: CGKeyCode(self.input.keyCode),
                            keyDown: false)

        if self.input.modifiers.contains(.command) {
            keyDown?.flags = CGEventFlags.maskCommand
            keyUp?.flags = CGEventFlags.maskCommand
        }

        if self.input.modifiers.contains(.control) {
            keyDown?.flags = CGEventFlags.maskControl
            keyUp?.flags = CGEventFlags.maskControl
        }

        if self.input.modifiers.contains(.option) {
            keyDown?.flags = CGEventFlags.maskAlternate
            keyUp?.flags = CGEventFlags.maskAlternate
        }

        if self.input.modifiers.contains(.shift) {
            keyDown?.flags = CGEventFlags.maskShift
            keyUp?.flags = CGEventFlags.maskShift
        }

        return [keyDown, keyUp]
    }

    private func press() {
        let source: CGEventSource? = CGEventSource(stateID: .hidSystemState)

        let pressEvents = self.input.isMouseInput
                            ? generateMouseClickEvents(source: source)
                            : generateKeyPressEvents(source: source)

        var completedPressesThisAction = 0

        while completedPressesThisAction < self.amountOfPresses {
            for event in pressEvents {
                event!.post(tap: .cghidEventTap)

                LoggerService.simPress(input: self.input, location: event!.location)
            }

            completedPressesThisAction += 1
        }
    }
}
