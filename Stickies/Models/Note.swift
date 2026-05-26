import Foundation
import CoreGraphics

struct Note: Codable, Identifiable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var text: String
    var frame: NoteFrame
    var tintStyle: NoteTintStyle
    var isHidden: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         text: String = "",
         frame: NoteFrame,
         tintStyle: NoteTintStyle = .slate,
         isHidden: Bool = false,
         createdAt: Date = .init(),
         updatedAt: Date = .init()) {
        self.schemaVersion = 2
        self.id = id
        self.text = text
        self.frame = frame
        self.tintStyle = tintStyle
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, text, frame, tintStyle, isHidden, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.frame = try c.decode(NoteFrame.self, forKey: .frame)
        self.tintStyle = (try? c.decode(NoteTintStyle.self, forKey: .tintStyle)) ?? .slate
        self.isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

/// AppKit-coordinate rect (origin bottom-left), stored as primitives for stable JSON.
struct NoteFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    init(_ r: CGRect) { self.x = r.origin.x; self.y = r.origin.y; self.w = r.size.width; self.h = r.size.height }
}

/// How much the dark palette tints the frosted-glass background.
/// Stored as a stable string so JSON on disk stays readable.
enum NoteTintStyle: String, Codable, CaseIterable {
    case mist       // lightest — barely tinted
    case smoke      // light frosted
    case slate      // default — balanced dark
    case obsidian   // darkest — near-opaque

    /// Opacity of the dark tint overlay on top of the system blur.
    var tintOpacity: Double {
        switch self {
        case .mist:     return 0.00
        case .smoke:    return 0.08
        case .slate:    return 0.18
        case .obsidian: return 0.38
        }
    }

    /// Swatch lightness used for the picker circles (0 = black, 1 = white).
    /// Darker note = darker swatch.
    var swatchLightness: Double {
        switch self {
        case .mist:     return 0.92
        case .smoke:    return 0.70
        case .slate:    return 0.35
        case .obsidian: return 0.15
        }
    }
}
