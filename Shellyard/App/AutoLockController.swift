//
//  AutoLockController.swift
//  Shellyard
//

import AppKit
import Foundation

/// Locks the document when it rests too long, or when the Mac sleeps.
///
/// Use means an event that reaches Shellyard: a key, a click, or a scroll.
/// Time spent in another application counts as rest, the way a password
/// manager counts it.
@MainActor
final class AutoLockController: ObservableObject {
    private weak var store: DocumentStore?
    private weak var sessions: SessionsController?
    private var lastActivity = ContinuousClock.now

    /// The monitor, the timer, and the observer live as long as the
    /// application, so nothing here is ever torn down.
    private var eventMonitor: Any?
    private var timer: Timer?
    private var sleepObserver: (any NSObjectProtocol)?

    init(store: DocumentStore, sessions: SessionsController) {
        self.store = store
        self.sessions = sessions

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            // The monitor runs on the main thread, but its closure carries no
            // isolation, so the fact is asserted rather than assumed silently.
            MainActor.assumeIsolated { self?.lastActivity = .now }
            return event
        }

        // The timer compares against the setting on every tick, so a change
        // in the Settings window needs no restart.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockIfIdle() }
        }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AppSettings.locksOnSleep else { return }
                self?.lockNow()
            }
        }
    }

    private func lockIfIdle() {
        guard let store, store.isUnlocked else { return }
        let minutes = AppSettings.autoLockMinutes
        guard minutes > 0,
              ContinuousClock.now - lastActivity >= .seconds(minutes * 60)
        else { return }
        lockNow()
    }

    /// The store closes every session before it locks: see
    /// `DocumentStore.willClose`.
    private func lockNow() {
        guard let store, store.isUnlocked else { return }
        store.lock()
    }
}
