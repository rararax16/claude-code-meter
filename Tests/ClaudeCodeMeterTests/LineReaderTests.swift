import Testing
import Foundation
@testable import ClaudeCodeMeter

@Suite("LineReader")
struct LineReaderTests {

    // 一時ファイルを作って FileHandle を返す。テスト終了時に削除。
    private func makeHandle(_ content: Data) throws -> (FileHandle, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linereader-\(UUID().uuidString).bin")
        try content.write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        return (handle, url)
    }

    @Test func singleShortLine() throws {
        let (handle, url) = try makeHandle(Data("hello\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = LineReader(handle: handle)
        #expect(reader.nextLine() == "hello")
        #expect(reader.nextLine() == nil)
    }

    @Test func multipleLines() throws {
        let (handle, url) = try makeHandle(Data("a\nbb\nccc\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = LineReader(handle: handle)
        #expect(reader.nextLine() == "a")
        #expect(reader.nextLine() == "bb")
        #expect(reader.nextLine() == "ccc")
        #expect(reader.nextLine() == nil)
    }

    @Test func lastLineWithoutTrailingNewline() throws {
        let (handle, url) = try makeHandle(Data("foo\nbar".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = LineReader(handle: handle)
        #expect(reader.nextLine() == "foo")
        #expect(reader.nextLine() == "bar")
        #expect(reader.nextLine() == nil)
    }

    @Test func emptyFile() throws {
        let (handle, url) = try makeHandle(Data())
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = LineReader(handle: handle)
        #expect(reader.nextLine() == nil)
    }

    // maxLineSize を超える行は捨てる (バッファだけが大きい状態でも、改行検出後の長さでも)
    @Test func skipsLineExceedingMaxSize() throws {
        // maxLineSize=10 で 20バイトの行 + 改行 + 次行
        var data = Data(repeating: 0x41, count: 20)  // "AAAA..." 20回
        data.append(0x0A)
        data.append(Data("next\n".utf8))
        let (handle, url) = try makeHandle(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = LineReader(handle: handle, maxLineSize: 10)
        // 1行目: 20バイトで maxLineSize 超 → nil (ファイル内残りも諦める)
        #expect(reader.nextLine() == nil)
    }

    // 「上限を超えた直後の chunk に改行が入っている」境界ケース
    @Test func strictBoundaryWhenNewlineInOverflowingChunk() throws {
        // maxLineSize=100、データ=110 'A' + '\n' を一気に書く
        var data = Data(repeating: 0x41, count: 110)
        data.append(0x0A)
        let (handle, url) = try makeHandle(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = LineReader(handle: handle, maxLineSize: 100)
        // 改行は見つかるが、それまでの長さ 110 > 100 なので nil を返すべき
        #expect(reader.nextLine() == nil)
    }

    @Test func acceptsLineAtExactBoundary() throws {
        // maxLineSize=100、ちょうど 100 バイトの行 + 改行
        var data = Data(repeating: 0x41, count: 100)
        data.append(0x0A)
        let (handle, url) = try makeHandle(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = LineReader(handle: handle, maxLineSize: 100)
        let line = reader.nextLine()
        #expect(line?.count == 100)
    }
}
