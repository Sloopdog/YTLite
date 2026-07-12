import Foundation

struct CommandPlan: Equatable {
    var arguments: [String]
    var warnings: [String]
}

enum ArgumentCompiler {
    static func makePlan(
        url: String,
        settings: DownloadSettings,
        preferences: ToolPreferences,
        ffmpegPath: String?,
        javaScriptRuntimePath: String? = nil,
        catalog: OptionCatalog,
        selections: [String: AdvancedSelection],
        customArguments: String
    ) -> CommandPlan {
        var arguments: [String] = []
        var warnings: [String] = []

        if !preferences.useUserConfiguration {
            arguments.append("--ignore-config")
        }

        arguments += [
            "--color", "never",
            "--newline",
            "--no-simulate",
            "--progress",
            "--progress-delta", "0.2",
            "--progress-template", "download:__YTLITE_PROGRESS__%(progress)j",
            "--progress-template", "postprocess:__YTLITE_POST__%(progress)j",
            "--print", "before_dl:__YTLITE_TITLE__%(.{title,id,webpage_url})j",
            "--print", "after_move:__YTLITE_RESULT__%(.{filepath,title,id,ext})j",
            "--paths", settings.outputDirectory,
            "--output", settings.filenameTemplate
        ]

        if let ffmpegPath, !ffmpegPath.isEmpty {
            arguments += ["--ffmpeg-location", ffmpegPath]
        }
        if let runtime = ToolLocator.javaScriptRuntimeArgument(path: javaScriptRuntimePath) {
            arguments += ["--js-runtimes", runtime]
        }

        arguments += mediaArguments(settings)

        if !settings.includePlaylist {
            arguments.append("--no-playlist")
        }
        if settings.embedMetadata { arguments.append("--embed-metadata") }
        if settings.embedThumbnail { arguments.append("--embed-thumbnail") }
        if settings.embedChapters { arguments.append("--embed-chapters") }

        if settings.downloadSubtitles {
            arguments += ["--write-subs", "--sub-langs", settings.subtitleLanguages]
            if settings.autoSubtitles { arguments.append("--write-auto-subs") }
            if settings.mediaMode == .video { arguments.append("--embed-subs") }
        }

        if settings.sponsorBlock {
            arguments += [
                "--sponsorblock-remove",
                "sponsor,selfpromo,interaction,intro,outro,preview,music_offtopic"
            ]
        }

        if settings.cookieBrowser != .none {
            arguments += ["--cookies-from-browser", settings.cookieBrowser.rawValue]
        }
        if settings.concurrentFragments > 1 {
            arguments += ["--concurrent-fragments", String(settings.concurrentFragments)]
        }
        if !settings.speedLimit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--limit-rate", settings.speedLimit.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        if settings.useDownloadArchive {
            let archive = URL(fileURLWithPath: settings.outputDirectory)
                .appendingPathComponent(".ytlite-download-archive.txt").path
            arguments += ["--download-archive", archive]
        }

        let selectedDefinitions = catalog.allOptions.filter { selections[$0.id]?.enabled == true }
        let orderedDefinitions = selectedDefinitions.sorted { lhs, rhs in
            let lhsReset = lhs.canonicalFlag.hasPrefix("--no-") || lhs.help.hasPrefix("Clear ") || lhs.help.hasPrefix("Remove all")
            let rhsReset = rhs.canonicalFlag.hasPrefix("--no-") || rhs.help.hasPrefix("Clear ") || rhs.help.hasPrefix("Remove all")
            return lhsReset && !rhsReset
        }
        for definition in orderedDefinitions {
            guard let selection = selections[definition.id], selection.enabled else { continue }

            if definition.takesValue {
                let trimmedValue = selection.value.trimmingCharacters(in: .whitespacesAndNewlines)
                let occurrences: [String]
                if definition.repeatable {
                    occurrences = selection.value
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                } else {
                    occurrences = trimmedValue.isEmpty ? [] : [trimmedValue]
                }

                if occurrences.isEmpty {
                    if definition.valueOptional {
                        arguments.append(definition.canonicalFlag)
                    } else {
                        warnings.append("\(definition.canonicalFlag) needs a value and was skipped.")
                    }
                    continue
                }

                for occurrence in occurrences {
                    let expectedArity = Int(definition.nargs ?? "1") ?? 1
                    if expectedArity == 1 {
                        // This field already represents one argv value. Splitting
                        // it would corrupt paths, templates, regular expressions,
                        // and commands that legitimately contain spaces.
                        arguments += [definition.canonicalFlag, occurrence]
                    } else {
                        let tokens = ArgumentTokenizer.tokenize(occurrence)
                        guard tokens.count == expectedArity else {
                            warnings.append("\(definition.canonicalFlag) needs \(expectedArity) values and was skipped.")
                            continue
                        }
                        arguments.append(definition.canonicalFlag)
                        arguments.append(contentsOf: tokens)
                    }
                }
            } else {
                arguments.append(definition.canonicalFlag)
            }
        }

        let rawTokens = ArgumentTokenizer.tokenize(customArguments)
        if !rawTokens.isEmpty {
            arguments.append(contentsOf: rawTokens)
            warnings.append("Raw arguments are passed through exactly as entered.")
        }

        arguments += ["--", url]
        return CommandPlan(arguments: arguments, warnings: warnings)
    }

    private static func mediaArguments(_ settings: DownloadSettings) -> [String] {
        switch settings.mediaMode {
        case .video:
            let format: String
            if let height = settings.videoQuality.heightLimit {
                format = "bv*[height<=\(height)]+ba/b[height<=\(height)]"
            } else {
                format = "bv*+ba/b"
            }

            var result = ["--format", format]
            switch settings.videoContainer {
            case .automatic:
                break
            case .mp4:
                result += [
                    "--format-sort", "vcodec:h264,acodec:aac,res,fps,hdr:12",
                    "--merge-output-format", "mp4",
                    "--remux-video", "mp4"
                ]
            case .mkv:
                result += ["--merge-output-format", "mkv", "--remux-video", "mkv"]
            case .webm:
                result += [
                    "--format-sort", "vcodec:vp9,acodec:opus,res,fps",
                    "--merge-output-format", "webm",
                    "--recode-video", "webm"
                ]
            }
            return result

        case .audio:
            var result = ["--format", "bestaudio/best", "--extract-audio", "--audio-format", settings.audioFormat.rawValue]
            if settings.audioFormat == .mp3 {
                result += ["--audio-quality", "0"]
            }
            return result

        case .original:
            return ["--format", "bestvideo*+bestaudio/best"]
        }
    }

    static func displayCommand(executable: String, arguments: [String], redactingSecrets: Bool = true) -> String {
        let renderedArguments = redactingSecrets ? redactSecrets(arguments) : arguments
        return ([executable] + renderedArguments).map(shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+=,-")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func redactSecrets(_ arguments: [String]) -> [String] {
        let secretFlags: Set<String> = [
            "--password", "--video-password", "--ap-password",
            "--client-certificate-password", "--twofactor", "--username", "--ap-username",
            "--add-headers", "--proxy", "--geo-verification-proxy", "--extractor-args",
            "--netrc-cmd", "--cookies", "--client-certificate", "--client-certificate-key",
            "-p", "-2", "-u"
        ]
        var result = arguments
        var redactNext = false
        for index in result.indices {
            if redactNext {
                result[index] = "••••••••"
                redactNext = false
                continue
            }
            let token = result[index]
            if secretFlags.contains(token) {
                redactNext = true
            } else if secretFlags.contains(where: { token.hasPrefix($0 + "=") }) {
                result[index] = token.prefix(while: { $0 != "=" }) + "=••••••••"
            } else if ["-p", "-2", "-u"].contains(where: { token.hasPrefix($0) && token.count > $0.count }) {
                result[index] = String(token.prefix(2)) + "••••••••"
            }
        }
        return result
    }
}

enum ArgumentTokenizer {
    static func tokenize(_ input: String) -> [String] {
        enum Quote { case single, double }
        var result: [String] = []
        var current = ""
        var quote: Quote?
        var escaping = false
        var tokenStarted = false

        func finishToken() {
            if tokenStarted {
                result.append(current)
                current = ""
                tokenStarted = false
            }
        }

        for character in input {
            if escaping {
                current.append(character)
                tokenStarted = true
                escaping = false
                continue
            }

            if character == "\\" && quote != .single {
                escaping = true
                tokenStarted = true
                continue
            }

            switch quote {
            case .single:
                if character == "'" { quote = nil } else { current.append(character) }
                tokenStarted = true
            case .double:
                if character == "\"" { quote = nil } else { current.append(character) }
                tokenStarted = true
            case nil:
                if character == "'" {
                    quote = .single
                    tokenStarted = true
                } else if character == "\"" {
                    quote = .double
                    tokenStarted = true
                } else if character.isWhitespace {
                    finishToken()
                } else {
                    current.append(character)
                    tokenStarted = true
                }
            }
        }

        if escaping { current.append("\\") }
        finishToken()
        return result
    }
}
