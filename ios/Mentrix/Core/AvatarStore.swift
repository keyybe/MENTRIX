import UIKit

// Фото профиля хранится только на устройстве: в папке приложения, уменьшенное до 512×512.
nonisolated enum AvatarStore {
    private static let size: CGFloat = 512

    private static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "avatars", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for file: String) -> URL {
        directory.appending(path: file)
    }

    // Возвращает имя сохранённого файла. Имя каждый раз новое, чтобы картинка обновилась на экране.
    static func save(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            // обрезаем по центру до квадрата и уменьшаем; UIImage сам учитывает поворот снимка из EXIF
            let side = min(image.size.width, image.size.height)
            let scale = size / side
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            let jpeg = renderer.jpegData(withCompressionQuality: 0.9) { _ in
                image.draw(in: CGRect(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2,
                                      width: drawSize.width, height: drawSize.height))
            }
            let file = "avatar_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
            try jpeg.write(to: url(for: file), options: .atomic)
            return file
        }.value
    }

    static func delete(_ file: String?) {
        guard let file else { return }
        try? FileManager.default.removeItem(at: url(for: file))
    }

    static func load(_ file: String?) -> UIImage? {
        guard let file else { return nil }
        return UIImage(contentsOfFile: url(for: file).path(percentEncoded: false))
    }
}
