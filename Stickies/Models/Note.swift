import Foundation
import CoreGraphics

struct Note: Codable, Identifiable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var text: String
    var frame: NoteFrame
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         text: String = "",
         frame: NoteFrame,
         createdAt: Date = .init(),
         updatedAt: Date = .init()) {
        self.schemaVersion = 1
        self.id = id
        self.text = text
        self.frame = frame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, text, frame, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.id = try c.decode(UUID.self, forKey: .id)
        self.text = try c.decode(String.self, forKey: .text)
        self.frame = try c.decode(NoteFrame.self, forKey: .frame)
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
