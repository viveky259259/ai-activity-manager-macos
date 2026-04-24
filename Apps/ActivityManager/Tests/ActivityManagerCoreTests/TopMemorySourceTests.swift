import Testing
@testable import ActivityManagerCore

@Suite("TopMemorySource.parseMem")
struct TopMemorySourceTests {
    @Test("parses kilobytes suffix")
    func kilobytes() {
        #expect(TopMemorySource.parseMem("3696K") == 3696 * 1024)
        #expect(TopMemorySource.parseMem("12K") == 12 * 1024)
    }

    @Test("parses megabytes suffix")
    func megabytes() {
        #expect(TopMemorySource.parseMem("23M") == 23 * 1024 * 1024)
        #expect(TopMemorySource.parseMem("750M") == 750 * 1024 * 1024)
    }

    @Test("parses gigabytes suffix")
    func gigabytes() {
        #expect(TopMemorySource.parseMem("2G") == 2 * 1024 * 1024 * 1024)
    }

    @Test("parses fractional values — top emits `1065M` but some locales use `1.04G`")
    func fractional() {
        let v = TopMemorySource.parseMem("1.5G")
        #expect(v == UInt64(1.5 * 1024 * 1024 * 1024))
    }

    @Test("bare digit treated as bytes")
    func bareDigit() {
        #expect(TopMemorySource.parseMem("1024") == 1024)
    }

    @Test("rejects malformed input")
    func invalid() {
        #expect(TopMemorySource.parseMem("abc") == nil)
        #expect(TopMemorySource.parseMem("") == nil)
    }
}
