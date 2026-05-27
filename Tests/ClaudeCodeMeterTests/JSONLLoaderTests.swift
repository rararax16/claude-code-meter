import Testing
import Foundation
@testable import ClaudeCodeMeter

@Suite("JSONLLoader security boundaries")
struct JSONLLoaderTests {

    // テスト用の一時ディレクトリ構造を作るヘルパ。
    // root/
    //   projects/         ← 集計対象 (root の中身)
    //   projects_evil/    ← 兄弟、抜けられたら NG
    private struct Sandbox {
        let root: URL              // 集計対象とする projects/ にあたるディレクトリ
        let evil: URL              // 兄弟ディレクトリ
        let cleanup: () -> Void
    }

    private func makeSandbox() throws -> Sandbox {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccmeter-test-\(UUID().uuidString)")
        let projects = base.appendingPathComponent("projects")
        let evil = base.appendingPathComponent("projects_evil")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
        return Sandbox(
            root: projects,
            evil: evil,
            cleanup: { try? FileManager.default.removeItem(at: base) }
        )
    }

    // 有効な assistant 行を作るユーティリティ。
    private func assistantLine(id: String, model: String = "claude-opus-4-7",
                               timestamp: String, input: Int = 1000, output: Int = 100) -> String {
        let obj: [String: Any] = [
            "type": "assistant",
            "timestamp": timestamp,
            "message": [
                "id": id,
                "model": model,
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    @Test func picksUpRegularJsonlInsideRoot() throws {
        let sb = try makeSandbox()
        defer { sb.cleanup() }

        let file = sb.root.appendingPathComponent("session1.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        try assistantLine(id: "msg-1", timestamp: now).write(to: file, atomically: true, encoding: .utf8)

        let result = JSONLLoader.load(since: Date().addingTimeInterval(-3600), root: sb.root)
        #expect(result.scannedFiles == 1)
        #expect(result.usedFiles == 1)
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.id == "msg-1")
    }

    // ~/.claude/projects/<x>/escape.jsonl → ~/.claude/projects_evil/secret.jsonl への symlink。
    // resolvedPath が projects/ 外に出るので拒否されるはず。
    @Test func rejectsSymlinkEscapingToSiblingDirectory() throws {
        let sb = try makeSandbox()
        defer { sb.cleanup() }

        // 攻撃ターゲット
        let secret = sb.evil.appendingPathComponent("secret.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        try assistantLine(id: "leaked", timestamp: now).write(to: secret, atomically: true, encoding: .utf8)

        // projects/escape.jsonl → projects_evil/secret.jsonl
        let symlink = sb.root.appendingPathComponent("escape.jsonl")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: secret)

        let result = JSONLLoader.load(since: Date().addingTimeInterval(-3600), root: sb.root)
        // scan はされるが、resolved が範囲外なので採用ゼロ
        #expect(result.entries.isEmpty, "symlink pointing outside projects/ must be ignored")
    }

    // projects 内に閉じた symlink (projects/a.jsonl → projects/sub/real.jsonl) は OK。
    @Test func acceptsSymlinkStayingWithinRoot() throws {
        let sb = try makeSandbox()
        defer { sb.cleanup() }
        let sub = sb.root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let real = sub.appendingPathComponent("real.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        try assistantLine(id: "ok", timestamp: now).write(to: real, atomically: true, encoding: .utf8)

        let symlink = sb.root.appendingPathComponent("alias.jsonl")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: real)

        let result = JSONLLoader.load(since: Date().addingTimeInterval(-3600), root: sb.root)
        // 実体は 1 メッセージだが、symlink 経由と実体経由で 2 度走査される可能性あり。
        // 重複は messageId で除去されるので entries.count == 1。
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.id == "ok")
    }

    // ディレクトリにわざと .jsonl 拡張子をつけたものは通常ファイルでないので拒否されるはず。
    @Test func rejectsDirectoryWithJsonlExtension() throws {
        let sb = try makeSandbox()
        defer { sb.cleanup() }
        let dir = sb.root.appendingPathComponent("fake.jsonl", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let result = JSONLLoader.load(since: Date().addingTimeInterval(-3600), root: sb.root)
        #expect(result.entries.isEmpty)
    }

    // 7日以上前のファイルは mtime で弾かれる。
    @Test func skipsFilesOlderThanCutoff() throws {
        let sb = try makeSandbox()
        defer { sb.cleanup() }

        let oldFile = sb.root.appendingPathComponent("old.jsonl")
        let oldTimestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86400))
        try assistantLine(id: "stale", timestamp: oldTimestamp).write(to: oldFile, atomically: true, encoding: .utf8)

        // mtime を 30日前にする
        let oldDate = Date().addingTimeInterval(-30 * 86400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldFile.path)

        let result = JSONLLoader.load(since: Date().addingTimeInterval(-7 * 86400), root: sb.root)
        #expect(result.entries.isEmpty)
    }
}
