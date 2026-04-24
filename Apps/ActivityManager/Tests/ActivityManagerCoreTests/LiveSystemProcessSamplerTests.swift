import Foundation
import Testing
@testable import ActivityManagerCore

/// Integration-ish smoke test. Runs only on macOS where libproc is available.
/// The test process itself must show up as one of the returned samples.
@Suite
@MainActor
struct LiveSystemProcessSamplerTests {
    @Test
    func capturesAtLeastTheTestProcess() {
        let sampler = LiveSystemProcessSampler()
        let snapshot = sampler.capture()

        #expect(snapshot.count > 1, "libproc should enumerate more than just PID 1")

        let myPID = getpid()
        let selfRow = snapshot.first(where: { $0.pid == myPID })
        #expect(selfRow != nil, "the test process must appear in its own snapshot")
        if let row = selfRow {
            #expect(row.threads >= 1)
            #expect(!row.user.isEmpty)
            // Own-process path should be readable.
            #expect(!row.executablePath.isEmpty)
        }
    }
}
