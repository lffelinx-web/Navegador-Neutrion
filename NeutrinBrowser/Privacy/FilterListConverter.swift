import Foundation
import JavaScriptCore

/// Converts EasyList-style filter lists into WebKit content-blocker JSON.
///
/// The conversion logic lives in NeutrinFilterConverter.js so the exact same code
/// is tested in Node (ScriptTests) and run here in JavaScriptCore.
enum FilterListConverter {
    /// Must match NEUTRIN_CONVERTER_VERSION in NeutrinFilterConverter.js.
    /// Bumping it makes the app re-download and re-convert lists.
    static let version = 1

    struct Output: Decodable {
        let version: Int
        let networkJSON: String
        let cosmeticJSON: String
        let blockDomains: [String]
        let exceptionDomains: [String]
        let stats: Stats
    }

    struct Stats: Decodable {
        let networkRules: Int
        let cosmeticRules: Int
        let skipped: Int
    }

    enum ConversionError: LocalizedError {
        case scriptMissing
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing: "Falta el conversor de filtros en la app."
            case .failed(let reason): "No se pudo convertir la lista (\(reason))."
            }
        }
    }

    /// CPU-heavy: call it off the main thread.
    static func convert(_ text: String) throws -> Output {
        guard let url = Bundle.main.url(forResource: "NeutrinFilterConverter", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw ConversionError.scriptMissing
        }
        guard let context = JSContext() else { throw ConversionError.failed("sin contexto de JavaScript") }

        var scriptError: String?
        context.exceptionHandler = { _, exception in
            scriptError = exception?.toString() ?? "unknown error"
        }
        context.evaluateScript(source)

        guard let convert = context.objectForKeyedSubscript("neutrinConvertFilterList"),
              !convert.isUndefined,
              let result = convert.call(withArguments: [text]),
              scriptError == nil,
              let json = result.toString() else {
            throw ConversionError.failed(scriptError ?? "sin resultado")
        }
        return try JSONDecoder().decode(Output.self, from: Data(json.utf8))
    }
}
