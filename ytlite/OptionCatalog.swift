import Foundation

struct OptionCatalog: Codable, Equatable {
    var schemaVersion: Int
    var ytDlpVersion: String
    var generatedAt: String
    var groups: [OptionGroup]

    var optionCount: Int { groups.reduce(0) { $0 + $1.options.count } }
    var allOptions: [AdvancedOptionDefinition] { groups.flatMap(\.options) }

    static let empty = OptionCatalog(schemaVersion: 1, ytDlpVersion: "Unknown", generatedAt: "", groups: [])
}
struct OptionGroup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var options: [AdvancedOptionDefinition]
}

struct AdvancedOptionDefinition: Codable, Identifiable, Equatable {
    var id: String
    var canonicalFlag: String
    var flags: [String]
    var signature: String
    var action: String
    var nargs: String?
    var metavar: String?
    var choices: [String]
    var help: String
    var repeatable: Bool
    var takesValue: Bool
    var valueOptional: Bool
    var defaultValue: String?
    var safety: OptionSafety

    var valuePrompt: String {
        if let metavar, !metavar.isEmpty { return metavar }
        return takesValue ? "VALUE" : ""
    }

    var isSensitive: Bool { safety == .password }
}

enum OptionSafety: String, Codable, Equatable {
    case normal
    case exec
    case plugin
    case fileURL = "file-url"
    case certificateBypass = "cert-bypass"
    case password

    var label: String? {
        switch self {
        case .normal: nil
        case .exec: "Runs commands"
        case .plugin: "Loads code"
        case .fileURL: "Local file access"
        case .certificateBypass: "Weakens security"
        case .password: "Sensitive"
        }
    }

    var symbol: String {
        switch self {
        case .normal: "checkmark.shield"
        case .exec: "terminal.fill"
        case .plugin: "puzzlepiece.extension.fill"
        case .fileURL: "folder.badge.gearshape"
        case .certificateBypass: "exclamationmark.shield.fill"
        case .password: "key.fill"
        }
    }
}

enum OptionCatalogLoader {
    static func load(bundle: Bundle = .main) throws -> OptionCatalog {
        guard let url = bundle.url(forResource: "OptionCatalog", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(OptionCatalog.self, from: data)
    }

    enum CatalogError: LocalizedError {
        case resourceMissing

        var errorDescription: String? {
            "The bundled yt-dlp option catalog could not be found."
        }
    }
}
