import Foundation
import ClawChatKit

enum StoredMessageAttachmentType: String, Codable, Hashable {
    case image
    case video
    case audio
    case file
}

struct StoredMessageAttachment: Identifiable, Codable, Hashable {
    let id: String
    let type: StoredMessageAttachmentType
    let filename: String
    let mimeType: String
    let size: Int

    var iconName: String {
        switch type {
        case .image:
            "photo"
        case .video:
            "video"
        case .audio:
            "waveform"
        case .file:
            "doc"
        }
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct ComposerAttachment: Identifiable, Hashable {
    let id: String
    let type: MessageAttachmentType
    let filename: String
    let mimeType: String
    let size: Int
    let dataBase64: String

    var iconName: String {
        switch type {
        case .image:
            "photo"
        case .video:
            "video"
        case .audio:
            "waveform"
        case .file:
            "doc"
        }
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var protocolAttachment: MessageAttachment {
        MessageAttachment(
            type: type,
            mimeType: mimeType,
            filename: filename,
            size: size,
            data: dataBase64
        )
    }

    var storedAttachment: StoredMessageAttachment {
        StoredMessageAttachment(
            id: id,
            type: StoredMessageAttachmentType(rawValue: type.rawValue) ?? .file,
            filename: filename,
            mimeType: mimeType,
            size: size
        )
    }
}
