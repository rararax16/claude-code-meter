import Foundation

enum JSONLLoader {
    // 1ファイルの上限。Claude Code の実 .jsonl は通常 ~10MB 以下なので、
    // これを超えるものはエラーまたは攻撃面とみなしてスキップ。
    private static let maxFileSize: Int = 100 * 1024 * 1024   // 100 MB
    // 1行の上限。長すぎる行は LineReader を膨張させる DoS になり得るのでスキップ。
    private static let maxLineSize: Int = 8 * 1024 * 1024     // 8 MB

    static var claudeProjectsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    struct Result {
        let entries: [UsageEntry]
        let scannedFiles: Int
        let usedFiles: Int
    }

    // テスト時は root を差し替えられるようにしている。本番は claudeProjectsDirectory を使う。
    static func load(since cutoff: Date, root: URL? = nil) -> Result {
        let root = (root ?? claudeProjectsDirectory).standardizedFileURL.resolvingSymlinksInPath()
        // パス区切りまで含めてプレフィクス判定するための文字列。
        // 例: rootPath = "/Users/main/.claude/projects"
        //     rootPrefix = "/Users/main/.claude/projects/"
        let rootPath = root.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey, .contentModificationDateKey, .fileSizeKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return Result(entries: [], scannedFiles: 0, usedFiles: 0)
        }

        var seen: Set<String> = []
        var entries: [UsageEntry] = []
        var scanned = 0
        var used = 0

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            scanned += 1

            // symlink を解決し、~/.claude/projects 配下に限定。
            // hasPrefix(rootPath) だと "projects_evil/..." も通ってしまうので、
            // 区切り込み (rootPrefix) で厳密判定する。
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let resolvedPath = resolved.path
            guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPrefix) else {
                continue
            }

            // FIFO・デバイスファイル・ディレクトリなどを除外。
            // ファイルサイズ上限・最終更新時刻チェックも一緒に。
            guard let res = try? resolved.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
            ]) else { continue }
            guard res.isRegularFile == true else { continue }
            if let size = res.fileSize, size > maxFileSize { continue }
            if let mtime = res.contentModificationDate, mtime < cutoff { continue }

            let added = parseFile(at: resolved, since: cutoff, seen: &seen, into: &entries)
            if added > 0 { used += 1 }
        }

        entries.sort { $0.timestamp < $1.timestamp }
        return Result(entries: entries, scannedFiles: scanned, usedFiles: used)
    }

    @discardableResult
    private static func parseFile(
        at url: URL,
        since cutoff: Date,
        seen: inout Set<String>,
        into entries: inout [UsageEntry]
    ) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }

        let reader = LineReader(handle: handle, maxLineSize: maxLineSize)
        var added = 0

        while let line = reader.nextLine() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            guard (obj["type"] as? String) == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            guard let timestampStr = obj["timestamp"] as? String,
                  let timestamp = isoWithFraction.date(from: timestampStr)
                                ?? isoNoFraction.date(from: timestampStr),
                  timestamp >= cutoff
            else { continue }

            guard let messageId = message["id"] as? String else { continue }
            if seen.contains(messageId) { continue }
            seen.insert(messageId)

            let model = (message["model"] as? String) ?? "unknown"
            let input = (usage["input_tokens"] as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            let cacheWrite = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

            if input == 0 && output == 0 && cacheWrite == 0 && cacheRead == 0 { continue }

            entries.append(UsageEntry(
                id: messageId,
                timestamp: timestamp,
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheWriteTokens: cacheWrite,
                cacheReadTokens: cacheRead
            ))
            added += 1
        }
        return added
    }
}

// 行読みヘルパ。searchFrom をキャリーして O(n)、maxLineSize で行が異常に長い時は
// 残りファイルを諦めて nil を返す (LineReader 利用側はファイルパースを終える)。
final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var searchFrom: Int = 0
    private let chunkSize = 1024 * 64
    private let newline: UInt8 = 0x0A
    private let maxLineSize: Int

    init(handle: FileHandle, maxLineSize: Int = 8 * 1024 * 1024) {
        self.handle = handle
        self.maxLineSize = maxLineSize
    }

    func nextLine() -> String? {
        while true {
            if searchFrom < buffer.count,
               let nl = buffer[searchFrom..<buffer.count].firstIndex(of: newline) {
                // 改行検出後にも厳密に行長を確認。chunk 読み込み直後に偶然改行が含まれていた
                // ケースで maxLineSize を超えた行を返してしまうのを防ぐ。
                if nl > maxLineSize {
                    return nil
                }
                let lineData = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                searchFrom = 0
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            searchFrom = buffer.count

            // 未改行のままバッファが上限を超えたら異常 (改行なしのまま GB クラスの読み込みを防ぐ)。
            if buffer.count > maxLineSize {
                return nil
            }

            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                if buffer.isEmpty { return nil }
                // 末尾の改行なし行も同じく長さ確認。
                if buffer.count > maxLineSize {
                    buffer.removeAll()
                    searchFrom = 0
                    return nil
                }
                let lineData = buffer
                buffer.removeAll()
                searchFrom = 0
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            buffer.append(chunk)
        }
    }
}
