import Foundation
import Testing
@testable import ActivityIPC

@Suite("IPC envelopes")
struct EnvelopeTests {
    @Test("Request round-trips through JSON preserving version + requestID + payload")
    func requestRoundTrip() throws {
        let payload = QueryRequest(
            question: "what did I work on yesterday?",
            range: DateInterval(start: Date(timeIntervalSince1970: 1), duration: 60)
        )
        let original = IPCRequest(payload: payload)

        let data = try IPCCoder.encoder().encode(original)
        let decoded = try IPCCoder.decoder().decode(IPCRequest<QueryRequest>.self, from: data)

        #expect(decoded.version == original.version)
        #expect(decoded.requestID == original.requestID)
        #expect(decoded.payload == original.payload)
    }

    @Test("Request defaults to IPCProtocol.version")
    func requestDefaultVersion() {
        let req = IPCRequest(payload: EmptyResponse())
        #expect(req.version == IPCProtocol.version)
    }

    @Test("Response.success round-trips")
    func responseSuccessRoundTrip() throws {
        let id = UUID()
        let body = StatusResponse(
            sources: ["frontmost", "idle"],
            capturedEventCount: 42,
            actionsEnabled: true,
            permissions: ["accessibility": "granted"]
        )
        let original = IPCResponse<StatusResponse>(requestID: id, result: .success(body))

        let data = try IPCCoder.encoder().encode(original)
        let decoded = try IPCCoder.decoder().decode(IPCResponse<StatusResponse>.self, from: data)

        #expect(decoded.requestID == id)
        switch decoded.result {
        case .success(let value): #expect(value == body)
        case .error: Issue.record("expected success")
        }
    }

    @Test("Response.error round-trips and preserves code + message")
    func responseErrorRoundTrip() throws {
        let id = UUID()
        let original = IPCResponse<StatusResponse>(requestID: id, result: .error(.versionMismatch))

        let data = try IPCCoder.encoder().encode(original)
        let decoded = try IPCCoder.decoder().decode(IPCResponse<StatusResponse>.self, from: data)

        #expect(decoded.requestID == id)
        switch decoded.result {
        case .success: Issue.record("expected error")
        case .error(let err):
            #expect(err == IPCError.versionMismatch)
            #expect(err.code == "version_mismatch")
        }
    }

    @Test("IPCError predefined constants have stable codes")
    func ipcErrorConstants() {
        #expect(IPCError.versionMismatch.code == "version_mismatch")
        #expect(IPCError.hostUnreachable.code == "host_unreachable")
        #expect(IPCError.invalidRequest.code == "invalid_request")
    }

    @Test("IPCProtocol exposes version and mach service name")
    func protocolConstants() {
        #expect(IPCProtocol.version == 1)
        #expect(IPCProtocol.machServiceName == "com.yourco.ActivityManager.ipc")
    }
}
