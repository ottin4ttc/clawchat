import UIKit

extension UIImage {
    func croppedToSquare(maxSize: CGFloat) -> UIImage {
        let side = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))

        guard let cgCropped = cgImage?.cropping(to: cropRect) else { return self }

        let targetSide = min(side, maxSize * UIScreen.main.scale)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide))
        return renderer.image { _ in
            UIImage(cgImage: cgCropped, scale: 1, orientation: imageOrientation)
                .draw(in: CGRect(origin: .zero, size: CGSize(width: targetSide, height: targetSide)))
        }
    }
}

enum AvatarStorage {
    private static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("agent_avatars", isDirectory: true)
    }

    private static func fileURL(for agentId: String) -> URL {
        directory.appendingPathComponent("\(agentId).jpg")
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func save(_ image: UIImage, for agentId: String) {
        ensureDirectory()
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: fileURL(for: agentId), options: .atomic)
        cachedImages[agentId] = image
    }

    static func load(for agentId: String) -> UIImage? {
        if let cached = cachedImages[agentId] { return cached }
        guard let data = try? Data(contentsOf: fileURL(for: agentId)),
              let image = UIImage(data: data) else { return nil }
        cachedImages[agentId] = image
        return image
    }

    static func loadCached(for agentId: String) -> UIImage? {
        cachedImages[agentId]
    }

    static func cacheInMemory(_ image: UIImage, for agentId: String) {
        cachedImages[agentId] = image
    }

    static func loadFromDisk(for agentId: String) async -> UIImage? {
        let url = fileURL(for: agentId)
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return nil as UIImage? }
            return image
        }.value
    }

    static func remove(for agentId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: agentId))
        cachedImages.removeValue(forKey: agentId)
    }

    private static var cachedImages: [String: UIImage] = [:]
}
