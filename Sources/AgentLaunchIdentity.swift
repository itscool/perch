import Foundation

/// Conservative support for the package entry points launched as argv[1].
/// A package document, utility, similar directory, or runtime option is not an
/// agent identity. Event and snapshot recognition use the same rule.
enum AgentLaunchIdentity {
    static func matches(script: String, target: String) -> Bool {
        guard !script.hasPrefix("-"), !script.split(separator: "/").contains("..") else { return false }
        switch target {
        case "codex": return script.hasSuffix("/@openai/codex/bin/codex.js")
        case "claude": return script.hasSuffix("/@anthropic-ai/claude-code/cli.js")
        default: return false
        }
    }
}
