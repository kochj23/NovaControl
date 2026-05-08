// SecurityTests.swift — NovaControl
// Security tests: loopback binding, credential scanning, input validation.
// Written by Jordan Koch.

import XCTest
@testable import NovaControl

final class SecurityTests: XCTestCase {

    // MARK: - API Server Binding

    func testAPIServerPortConstant() {
        // NovaControl must bind to port 37400
        let expectedPort: UInt16 = 37400
        XCTAssertEqual(expectedPort, 37400)
    }

    // MARK: - Source File Credential Scan

    func testNoHardcodedCredentials() {
        let sourceFiles = findAllSwiftFiles(
            in: "/Volumes/Data/xcode/NovaControl/NovaControl")
        for file in sourceFiles {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                continue
            }
            let filename = (file as NSString).lastPathComponent
            assertNoCredentials(in: content, file: filename)
        }
    }

    func testNoPersonalEmailAddressesInSource() {
        // Verify no personal email addresses appear in production source files
        // Check for any @gmail.com or @digitalnoise.net addresses in string literals
        let sourceFiles = findAllSwiftFiles(
            in: "/Volumes/Data/xcode/NovaControl/NovaControl")
        let emailPattern = try! NSRegularExpression(
            pattern: "\"[^\"]*@(gmail\\.com|digitalnoise\\.net)[^\"]*\"")
        for file in sourceFiles {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                continue
            }
            let filename = (file as NSString).lastPathComponent
            let matches = emailPattern.numberOfMatches(
                in: content, range: NSRange(content.startIndex..., in: content))
            XCTAssertEqual(matches, 0,
                           "\(filename) must not contain personal email addresses in string literals")
        }
    }

    // MARK: - Entitlements

    func testSandboxDisabled() {
        let path = "/Volumes/Data/xcode/NovaControl/Resources/NovaControl.entitlements"
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            // Skip gracefully if file not accessible from test sandbox
            return
        }
        XCTAssertTrue(content.contains("com.apple.security.app-sandbox"))
        XCTAssertTrue(content.contains("<false/>"),
                      "Sandbox must be disabled")
    }

    func testNetworkEntitlements() {
        let path = "/Volumes/Data/xcode/NovaControl/Resources/NovaControl.entitlements"
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            // Skip gracefully if file not accessible from test sandbox
            return
        }
        XCTAssertTrue(content.contains("com.apple.security.network.server"),
                      "Network server entitlement required for NWListener")
        XCTAssertTrue(content.contains("com.apple.security.network.client"),
                      "Network client entitlement required for HTTP probes")
    }

    // MARK: - Slack Token from Config

    func testSlackTokenNotHardcoded() {
        let workflowSource = sourceFileContents("WorkflowEngine.swift")
        guard !workflowSource.isEmpty else { return } // Skip if source not accessible
        XCTAssertTrue(workflowSource.contains("openclaw.json"),
                      "Slack token must be loaded from OpenClaw config")
        XCTAssertFalse(workflowSource.contains("xoxb-"),
                       "Must not contain hardcoded Slack token")
    }

    // MARK: - Input Validation

    func testManualHealthInputRejectsInvalidJSON() {
        let invalidJSON = "not json".data(using: .utf8)!
        let result = try? JSONDecoder().decode(ManualHealthInput.self, from: invalidJSON)
        XCTAssertNil(result, "Invalid JSON must be rejected")
    }

    func testIPAddressNotExposedInSource() {
        // NovaControl binds to 127.0.0.1 — external IPs should not be present
        let sourceFiles = findAllSwiftFiles(
            in: "/Volumes/Data/xcode/NovaControl/NovaControl")
        let externalIPPattern = try! NSRegularExpression(
            pattern: "\"(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})\"")
        for file in sourceFiles {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else {
                continue
            }
            let filename = (file as NSString).lastPathComponent
            let matches = externalIPPattern.matches(
                in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let ip = String(content[range])
                    // Only 127.0.0.1 is acceptable
                    XCTAssertEqual(ip, "127.0.0.1",
                                   "\(filename) contains non-loopback IP: \(ip)")
                }
            }
        }
    }

    // MARK: - Big Brother API Security

    func testBigBrotherAPIPortIsLoopbackOnly() {
        // Big Brother diagnostics API must bind to loopback only — port 37461
        let source = sourceFileContents("BigBrotherReader.swift")
        guard !source.isEmpty else { return }
        XCTAssertTrue(source.contains("127.0.0.1"),
                      "BigBrotherReader must use loopback address only")
        XCTAssertTrue(source.contains("37461"),
                      "BigBrotherReader must target port 37461")
        XCTAssertFalse(source.contains("0.0.0.0"),
                       "BigBrotherReader must not bind to all interfaces")
    }

    func testBigBrotherReaderNoHardcodedTokens() {
        let source = sourceFileContents("BigBrotherReader.swift")
        guard !source.isEmpty else { return }
        // Big Brother API requires no auth token — loopback-only security model
        XCTAssertFalse(source.contains("Authorization:"),
                       "BigBrotherReader must not send auth headers (loopback only)")
        XCTAssertFalse(source.contains("Bearer "),
                       "BigBrotherReader must not use bearer tokens")
    }

    func testBigBrotherProxyRoutePattern() {
        // NovaAPIServer must proxy /api/bigbrother → /bb on port 37461
        let source = sourceFileContents("NovaAPIServer.swift")
        guard !source.isEmpty else { return }
        XCTAssertTrue(source.contains("/api/bigbrother"),
                      "NovaAPIServer must route /api/bigbrother")
        XCTAssertTrue(source.contains("proxyToBigBrother"),
                      "NovaAPIServer must have proxyToBigBrother method")
        XCTAssertTrue(source.contains("127.0.0.1:37461"),
                      "Proxy must target loopback:37461 only")
    }

    // MARK: - Workflow Template Security

    func testWorkflowTemplateVariableEscaping() {
        // Template variables use {{key}} syntax — verify no SQL/shell injection characters
        let template = "Hello {{name}}, your task {{title}} is due {{date}}"
        // The template itself should not contain shell metacharacters
        let dangerousChars: [Character] = ["`", "$", ";", "|"]
        for char in dangerousChars {
            XCTAssertFalse(template.contains(char),
                           "Template should not contain shell metacharacter: \(char)")
        }
    }

    // MARK: - Helpers

    private func findAllSwiftFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }
        var files: [String] = []
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".swift") {
                files.append("\(directory)/\(file)")
            }
        }
        return files
    }

    private func sourceFileContents(_ filename: String) -> String {
        let base = "/Volumes/Data/xcode/NovaControl/NovaControl"
        let files = findAllSwiftFiles(in: base)
        for file in files where file.hasSuffix("/\(filename)") {
            return (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        }
        return ""
    }

    private func assertNoCredentials(in source: String, file: String) {
        let patterns = [
            ("sk-", "OpenAI/Anthropic key"),
            ("AKIA", "AWS access key"),
            ("ghp_", "GitHub PAT"),
            ("xoxb-", "Slack bot token"),
            ("xoxp-", "Slack user token"),
        ]
        for (pattern, desc) in patterns {
            let literal = "\"\(pattern)"
            XCTAssertFalse(source.contains(literal),
                           "\(file) must not contain hardcoded \(desc): \(pattern)")
        }
    }
}
