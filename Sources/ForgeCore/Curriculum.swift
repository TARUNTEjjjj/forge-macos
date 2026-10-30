import Foundation

public struct Curriculum: Decodable, Sendable {
    public let version: String
    public let totalHours: Int
    public let overview: CurriculumOverview
    public let resources: [LearningResource]
    public let phases: [LearningPhase]
    public let problems: [PracticeProblem]

    public var modules: [LearningModule] { phases.flatMap(\.modules) }
    public var moduleIDs: Set<String> { Set(modules.map(\.id)) }

    public static func loadBundled() throws -> Curriculum {
        // A packaged .app relocates SwiftPM resources into Contents/Resources.
        // Resolve that path before invoking SwiftPM's build-directory fallback.
        let relocatedBundle = Bundle.main.resourceURL?
            .appendingPathComponent("ForgeMac_ForgeCore.bundle")
        let relocatedURL = relocatedBundle.flatMap { Bundle(url: $0) }?
            .url(forResource: "curriculum", withExtension: "json")
        guard let url = relocatedURL ?? Bundle.module.url(forResource: "curriculum", withExtension: "json") else {
            throw CurriculumError.missingResource
        }
        let curriculum = try JSONDecoder().decode(Curriculum.self, from: Data(contentsOf: url))
        try curriculum.validate()
        return curriculum
    }

    public func validate() throws {
        guard !phases.isEmpty, totalHours > 0,
              Set(phases.map(\.id)).count == phases.count,
              moduleIDs.count == modules.count,
              modules.allSatisfy({ !$0.id.isEmpty && $0.hours > 0 && !$0.lessons.isEmpty }),
              phases.allSatisfy({ $0.hours == $0.modules.reduce(0) { $0 + $1.hours } }),
              phases.reduce(0, { $0 + $1.hours }) == totalHours else {
            throw CurriculumError.invalidStructure
        }
        var earlierPhases = Set<String>()
        for phase in phases {
            guard Set(phase.prerequisites).isSubset(of: earlierPhases) else {
                throw CurriculumError.invalidStructure
            }
            earlierPhases.insert(phase.id)
        }
    }
}

public enum CurriculumError: LocalizedError {
    case missingResource, invalidStructure
    public var errorDescription: String? {
        switch self {
        case .missingResource: "The bundled Forge curriculum could not be found. Reinstall the app."
        case .invalidStructure: "The curriculum failed its integrity check. Reinstall the app."
        }
    }
}

public struct CurriculumOverview: Decodable, Sendable {
    public let title: String
    public let audience: String
    public let promise: String
    public let pace: String
    public let languages: String
    public let method: String
}

public struct LearningPhase: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let hours: Int
    public let color: String
    public let prerequisites: [String]
    public let modules: [LearningModule]
}

public struct LearningModule: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let hours: Int
    public let lessons: [String]
    public let task: String
    public let successCriteria: [String]
    public let project: String
    public let resources: [LessonResource]
    public let codeExamples: [CodeExample]
}

public struct LessonResource: Decodable, Identifiable, Sendable {
    public var id: String { url.absoluteString + title }
    public let title: String
    public let url: URL
}

public struct LearningResource: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let provider: String
    public let topic: String
    public let description: String
}

public struct CodeExample: Decodable, Sendable {
    public let language: String
    public let code: String
    public let explanation: String
}

public struct PracticeProblem: Decodable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let platform: String
    public let difficulty: String
    public let topic: String
    public let phaseId: String
    public let practiceNote: String
}
