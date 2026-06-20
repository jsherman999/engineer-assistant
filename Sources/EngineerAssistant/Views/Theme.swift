import SwiftUI
import AppKit

/// A restrained, IDE-like palette. Surfaces use semantic system colors so they adapt to
/// light/dark; section accents are muted (used as thin rules, captions, and faint fills).
enum Theme {
    // Surfaces
    static let workspace = Color(nsColor: .underPageBackgroundColor)
    static let panel = Color(nsColor: .textBackgroundColor)
    static let bar = Color(nsColor: .windowBackgroundColor)

    // Section accents
    static let concept   = Color(red: 0.30, green: 0.56, blue: 0.92) // blue
    static let demos     = Color(red: 0.26, green: 0.70, blue: 0.46) // green
    static let practice  = Color(red: 0.90, green: 0.64, blue: 0.28) // amber
    static let challenge = Color(red: 0.67, green: 0.46, blue: 0.86) // purple
    static let headerTint = Color(red: 0.30, green: 0.56, blue: 0.92)

    // Terminal pane
    static let terminalBarBg = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let terminalBarFg = Color(red: 0.82, green: 0.85, blue: 0.90)
    static let terminalBackgroundNS = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    static let terminalForegroundNS = NSColor(calibratedRed: 0.84, green: 0.87, blue: 0.91, alpha: 1)
    static let terminalGreenNS = NSColor(calibratedRed: 0.36, green: 0.92, blue: 0.45, alpha: 1)
}
