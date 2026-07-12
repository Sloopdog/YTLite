import Foundation
import XCTest
@testable import YTLite

final class YTLiteTests: XCTestCase {
    func testTokenizerPreservesQuotedValuesWithoutUsingAShell() {
        XCTAssertEqual(
            ArgumentTokenizer.tokenize(#"--format "best video" --output 'A file.%(ext)s' escaped\ value"#),
            ["--format", "best video", "--output", "A file.%(ext)s", "escaped value"]
        )
    }

    func testCompilerPlacesURLAfterOptionTerminator() {
        let catalog = OptionCatalog.empty
        var settings = DownloadSettings.standard
        settings.outputDirectory = "/tmp/YT Lite Downloads"
        let plan = ArgumentCompiler.makePlan(
            url: "-https://example.com/video?id=1",
            settings: settings,
            preferences: ToolPreferences(),
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            catalog: catalog,
            selections: [:],
            customArguments: ""
        )
        XCTAssertEqual(plan.arguments.suffix(2), ["--", "-https://example.com/video?id=1"])
        XCTAssertTrue(plan.arguments.contains("--ignore-config"))
        XCTAssertTrue(plan.arguments.contains("--no-simulate"))
        XCTAssertTrue(plan.arguments.contains("/tmp/YT Lite Downloads"))
    }

    func testCompilerSkipsRequiredAdvancedOptionWithNoValue() {
        let option = AdvancedOptionDefinition(
            id: "--proxy",
            canonicalFlag: "--proxy",
            flags: ["--proxy"],
            signature: "--proxy URL",
            action: "store",
            nargs: "1",
            metavar: "URL",
            choices: [],
            help: "Proxy",
            repeatable: false,
            takesValue: true,
            valueOptional: false,
            defaultValue: nil,
            safety: .normal
        )
        let catalog = OptionCatalog(
            schemaVersion: 1,
            ytDlpVersion: "test",
            generatedAt: "",
            groups: [OptionGroup(id: "network", name: "Network", options: [option])]
        )
        let plan = ArgumentCompiler.makePlan(
            url: "https://example.com",
            settings: .standard,
            preferences: ToolPreferences(),
            ffmpegPath: nil,
            catalog: catalog,
            selections: ["--proxy": AdvancedSelection(enabled: true, value: "")],
            customArguments: ""
        )
        XCTAssertFalse(plan.arguments.contains("--proxy"))
        XCTAssertEqual(plan.warnings, ["--proxy needs a value and was skipped."])
    }

    func testSecretsAreRedactedFromCommandPreview() {
        let command = ArgumentCompiler.displayCommand(
            executable: "yt-dlp",
            arguments: ["--username", "michael", "--password", "very secret", "https://example.com"]
        )
        XCTAssertFalse(command.contains("very secret"))
        XCTAssertTrue(command.contains("••••••••"))
        XCTAssertFalse(command.contains("michael"))
    }

    func testProgressJSONIsDecoded() {
        let line = #"__YTLITE_PROGRESS__{"status":"downloading","downloaded_bytes":50,"total_bytes":200,"speed":1024,"eta":65}"#
        guard case let .progress(fraction, speed, eta) = ProgressDecoder.decode(line: line) else {
            return XCTFail("Expected a progress event")
        }
        XCTAssertEqual(fraction, 0.25)
        XCTAssertNotNil(speed)
        XCTAssertEqual(eta, "1:05")
    }

    func testGeneratedCatalogCoversAllCurrentParserOptions() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let catalogURL = testDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ytlite/Resources/OptionCatalog.json")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(OptionCatalog.self, from: data)
        XCTAssertEqual(catalog.ytDlpVersion, "2026.07.04")
        XCTAssertEqual(catalog.optionCount, 323)
        XCTAssertEqual(Set(catalog.allOptions.map(\.id)).count, catalog.optionCount)
        XCTAssertTrue(catalog.allOptions.contains { $0.id == "--exec" && $0.safety == .exec })
        XCTAssertTrue(catalog.allOptions.contains { $0.id == "--password" && $0.safety == .password })
        XCTAssertTrue(catalog.allOptions.contains { $0.id == "--twofactor" && $0.safety == .password })
        XCTAssertTrue(catalog.allOptions.contains { $0.id == "--username" && $0.safety == .password })
    }

    func testJavaScriptRuntimeIsPassedExplicitly() {
        XCTAssertEqual(
            ToolLocator.javaScriptRuntimeArgument(path: "/opt/homebrew/bin/deno"),
            "deno:/opt/homebrew/bin/deno"
        )
        XCTAssertEqual(
            ToolLocator.javaScriptRuntimeArgument(path: "/usr/local/bin/qjs"),
            "quickjs:/usr/local/bin/qjs"
        )
    }

    func testChannelProbeParsesFlatPlaylistEntries() throws {
        let json = #"{"channel":"Example Creator","entries":[{"id":"abc123","title":"Fresh upload","url":"https://www.youtube.com/watch?v=abc123"}]}"#
        let result = ChannelMonitorService.parse(Data(json.utf8))
        switch result {
        case let .success(probe):
            XCTAssertEqual(probe.channelName, "Example Creator")
            XCTAssertEqual(probe.videos, [ChannelVideo(id: "abc123", title: "Fresh upload", url: "https://www.youtube.com/watch?v=abc123")])
        case let .failure(error):
            XCTFail(error.localizedDescription)
        }
    }
}
