import Foundation
import CoreGraphics

struct Note: Codable, Identifiable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var text: String
    var hasRichBody: Bool
    var frame: NoteFrame
    var tintStyle: NoteTintStyle
    var isHidden: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         text: String = "",
         hasRichBody: Bool = false,
         frame: NoteFrame,
         tintStyle: NoteTintStyle = .slate,
         isHidden: Bool = false,
         createdAt: Date = .init(),
         updatedAt: Date = .init()) {
        self.schemaVersion = 3
        self.id = id
        self.text = text
        self.hasRichBody = hasRichBody
        self.frame = frame
        self.tintStyle = tintStyle
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, text, hasRichBody, frame, tintStyle, isHidden, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.hasRichBody = (try? c.decode(Bool.self, forKey: .hasRichBody)) ?? false
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

/// The four surfaces, running light to dark. Two light ones carrying dark
/// text, two dark ones carrying white. Appearance (material, overlay, colour
/// scheme) lives with the view in `NoteView.swift`.
/// Stored as a stable string so JSON on disk stays readable.
enum NoteTintStyle: String, Codable, CaseIterable {
    case mist       // lightest glass, dark text
    case smoke      // light glass, dark text
    case slate      // default - dark glass, white text
    case obsidian   // darkest, white text

    /// Swatch lightness used for the picker circles (0 = black, 1 = white).
    /// Darker note = darker swatch.
    var swatchLightness: Double {
        switch self {
        case .mist:     return 0.97
        case .smoke:    return 0.78
        case .slate:    return 0.34
        case .obsidian: return 0.11
        }
    }
}
