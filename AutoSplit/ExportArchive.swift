import Foundation

enum ExportArchive {
    // PDFs already contain compressed streams. Store those bytes in the ZIP
    // and let the PDF quality setting control the size and readability.
    static let partLimit: Int64 = 100_000_000

    static func fileStem(_ title: String) -> String {
        let name = NameFinder.safeName(title)
        guard name != ".", name != ".." else { return "Скан" }
        let visible = name.drop(while: { $0 == "." })
        var result = ""
        var bytes = 0
        for character in visible {
            let length = String(character).utf8.count
            guard bytes + length <= 220 else { break }
            result.append(character)
            bytes += length
        }
        return result.isEmpty ? "Скан" : result
    }

    static func makeParts(_ pdfs: [URL], task: URL?, in folder: URL, name: String) throws -> [URL] {
        let taskSize = try task.map(size) ?? 0
        let budget = partLimit - taskSize - 16_384
        var groups: [[URL]] = []
        var group: [URL] = []
        var used: Int64 = 0
        for pdf in pdfs {
            let cost = try size(pdf) + 1024
            guard cost <= budget else {
                throw ScanError.message("«\(pdf.lastPathComponent)» завеликий для ZIP до 100 МБ. Виберіть сильніше стиснення або експортуйте PDF окремо.")
            }
            if used + cost > budget {
                groups.append(group)
                group = []
                used = 0
            }
            group.append(pdf)
            used += cost
        }
        if !group.isEmpty { groups.append(group) }

        return try groups.enumerated().map { index, files in
            let suffix = groups.count == 1 ? "" : "_\(index + 1)-з-\(groups.count)"
            let zip = folder.appendingPathComponent(name + suffix + ".zip")
            try write(files + (task.map { [$0] } ?? []), to: zip)
            return zip
        }
    }

    private static func size(_ url: URL) throws -> Int64 {
        guard let count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw ScanError.message("Не вдалося визначити розмір файлу")
        }
        return Int64(count)
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0)
        }
        return crc
    }

    private static func write(_ files: [URL], to url: URL) throws {
        guard files.count < Int(UInt16.max) else { throw ScanError.message("Забагато файлів для одного ZIP") }
        try Data().write(to: url)
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        var directory = Data()
        let flags: UInt16 = 0x0808 // UTF-8 names and a data descriptor.
        for file in files {
            let name = Data(file.lastPathComponent.utf8)
            let offset = UInt32(try writer.offset())
            var header = Data()
            header.le(UInt32(0x04034b50))
            header.le(UInt16(20)); header.le(flags)
            header.le(UInt16(0)); header.le(UInt16(0)); header.le(UInt16(33))
            header.append(Data(repeating: 0, count: 12))
            header.le(UInt16(name.count)); header.le(UInt16(0))
            header.append(name)
            try writer.write(contentsOf: header)

            let reader = try FileHandle(forReadingFrom: file)
            defer { try? reader.close() }
            var crc = UInt32.max
            var count: UInt32 = 0
            while let block = try reader.read(upToCount: 256 * 1024), !block.isEmpty {
                for byte in block { crc = crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
                count += UInt32(block.count)
                try writer.write(contentsOf: block)
            }
            crc ^= UInt32.max
            var descriptor = Data()
            descriptor.le(UInt32(0x08074b50)); descriptor.le(crc)
            descriptor.le(count); descriptor.le(count)
            try writer.write(contentsOf: descriptor)

            directory.le(UInt32(0x02014b50))
            directory.le(UInt16(20)); directory.le(UInt16(20)); directory.le(flags)
            directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(33))
            directory.le(crc); directory.le(count); directory.le(count)
            directory.le(UInt16(name.count))
            directory.append(Data(repeating: 0, count: 12))
            directory.le(offset)
            directory.append(name)
        }
        let start = UInt32(try writer.offset())
        var end = Data()
        end.le(UInt32(0x06054b50)); end.le(UInt32(0))
        end.le(UInt16(files.count)); end.le(UInt16(files.count))
        end.le(UInt32(directory.count)); end.le(start); end.le(UInt16(0))
        try writer.write(contentsOf: directory)
        try writer.write(contentsOf: end)
        try writer.close()
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
