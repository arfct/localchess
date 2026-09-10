// Haptics.swift — LocalChess
// All haptics go through HapticManager: light tick for moves, heavy blast
// for captures, an extra-crazy multi-burst for queen captures and checkmate.
// Uses CoreHaptics custom patterns with UIKit fallbacks. Safe on simulator
// (haptics silently no-op where unsupported).

import Foundation
import CoreHaptics
import UIKit

final class HapticManager {
    static let shared = HapticManager()
    private var engine: CHHapticEngine?
    private var supportsCoreHaptics = false

    private init() {}

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            supportsCoreHaptics = true
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
                self?.supportsCoreHaptics = true
            }
            engine?.stoppedHandler = { [weak self] _ in self?.supportsCoreHaptics = false }
        } catch {
            supportsCoreHaptics = false
        }
    }

    // MARK: - Public events

    /// Light tick for a normal move.
    func move() {
        if play(pattern: Self.movePattern) { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Selection tick when lifting/selecting a piece.
    func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Heavy blast for captures. Queen captures get the crazy pattern.
    func capture(captured: PieceType?) {
        if captured == .queen { queenCapture(); return }
        if play(pattern: Self.capturePattern) { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Really crazy multi-burst for queen captures.
    func queenCapture() {
        if play(pattern: Self.queenCapturePattern) { return }
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { gen.impactOccurred(intensity: 1.0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    /// Alarm pulses for check.
    func check() {
        if play(pattern: Self.checkPattern) { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Full celebration for checkmate (win) / heavy error (loss).
    func checkmate(playerWon: Bool) {
        if play(pattern: playerWon ? Self.mateWinPattern : Self.mateLosePattern) { return }
        UINotificationFeedbackGenerator().notificationOccurred(playerWon ? .success : .error)
    }

    func gameStart() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func illegal() {
        if play(pattern: Self.illegalPattern) { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - Pattern player

    @discardableResult
    private func play(pattern events: [[String: Any]]) -> Bool {
        guard supportsCoreHaptics, let engine else { return false }
        do {
            let dict: [CHHapticPattern.Key: Any] = [.version: 1.0, .pattern: events]
            let pattern = try CHHapticPattern(dictionary: dict)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }

    private static func transient(
        time: Double, intensity: Double, sharpness: Double
    ) -> [String: Any] {
        [
            "Event": [
                "EventType": "HapticTransient",
                "Time": time,
                "EventParameters": [
                    ["ParameterID": "HapticIntensity", "ParameterValue": intensity],
                    ["ParameterID": "HapticSharpness", "ParameterValue": sharpness]
                ]
            ],
            "EventType": "HapticTransient",
            "Time": time,
            "EventParameters": [
                ["ParameterID": "HapticIntensity", "ParameterValue": intensity],
                ["ParameterID": "HapticSharpness", "ParameterValue": sharpness]
            ]
        ]
    }

    private static func continuous(
        time: Double, duration: Double, intensity: Double, sharpness: Double
    ) -> [String: Any] {
        [
            "Event": [
                "EventType": "HapticContinuous",
                "Time": time,
                "EventDuration": duration,
                "EventParameters": [
                    ["ParameterID": "HapticIntensity", "ParameterValue": intensity],
                    ["ParameterID": "HapticSharpness", "ParameterValue": sharpness]
                ]
            ],
            "EventType": "HapticContinuous",
            "Time": time,
            "EventDuration": duration,
            "EventParameters": [
                ["ParameterID": "HapticIntensity", "ParameterValue": intensity],
                ["ParameterID": "HapticSharpness", "ParameterValue": sharpness]
            ]
        ]
    }

    static let movePattern: [[String: Any]] = [
        transient(time: 0.0, intensity: 0.55, sharpness: 0.7)
    ]

    static let capturePattern: [[String: Any]] = [
        transient(time: 0.0, intensity: 1.0, sharpness: 0.9),
        continuous(time: 0.02, duration: 0.12, intensity: 0.8, sharpness: 0.4),
        transient(time: 0.1, intensity: 0.7, sharpness: 0.6)
    ]

    /// Extra-crazy: rapid heavy bursts + rumble tail.
    static let queenCapturePattern: [[String: Any]] = [
        transient(time: 0.0, intensity: 1.0, sharpness: 1.0),
        transient(time: 0.06, intensity: 1.0, sharpness: 0.9),
        transient(time: 0.12, intensity: 1.0, sharpness: 1.0),
        transient(time: 0.18, intensity: 0.9, sharpness: 0.7),
        continuous(time: 0.2, duration: 0.35, intensity: 1.0, sharpness: 0.3),
        transient(time: 0.42, intensity: 1.0, sharpness: 1.0)
    ]

    static let checkPattern: [[String: Any]] = [
        transient(time: 0.0, intensity: 0.9, sharpness: 0.8),
        transient(time: 0.12, intensity: 0.9, sharpness: 0.8),
        transient(time: 0.24, intensity: 1.0, sharpness: 0.9)
    ]

    /// Escalating celebration for delivering mate.
    static let mateWinPattern: [[String: Any]] = [
        transient(time: 0.0, intensity: 0.8, sharpness: 0.6),
        transient(time: 0.1, intensity: 0.9, sharpness: 0.7),
        transient(time: 0.2, intensity: 1.0, sharpness: 0.8),
        transient(time: 0.32, intensity: 1.0, sharpness: 1.0),
        transient(time: 0.42, intensity: 1.0, sharpness: 1.0),
        continuous(time: 0.5, duration: 0.6, intensity: 1.0, sharpness: 0.4),
        transient(time: 0.95, intensity: 1.0, sharpness: 1.0)
    ]

    static let mateLosePattern: [[String: Any]] = [
        continuous(time: 0.0, duration: 0.5, intensity: 1.0, sharpness: 0.2),
        transient(time: 0.55, intensity: 0.8, sharpness: 0.4)
    ]

    static let illegalPattern: [[String: Any]] = [
        transient(time: 0.0, intensity: 0.5, sharpness: 0.4)
    ]
}
