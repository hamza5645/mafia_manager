import Foundation

/// Comprehensive input validation for user-provided data
enum InputValidator {

    // MARK: - Validation Errors

    enum ValidationError: LocalizedError {
        case empty
        case tooShort(minimum: Int)
        case tooLong(maximum: Int)
        case invalidCharacters
        case containsNewlines
        case containsControlCharacters

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Cannot be empty"
            case .tooShort(let min):
                return "Must be at least \(min) characters"
            case .tooLong(let max):
                return "Must be \(max) characters or less"
            case .invalidCharacters:
                return "Contains invalid characters"
            case .containsNewlines:
                return "Cannot contain line breaks"
            case .containsControlCharacters:
                return "Contains invalid control characters"
            }
        }
    }

    // MARK: - Player Name Validation

    static func validatePlayerName(_ name: String) -> Result<String, ValidationError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check not empty
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }

        // Check length (1-50 characters)
        guard trimmed.count >= 1 else {
            return .failure(.tooShort(minimum: 1))
        }

        guard trimmed.count <= 50 else {
            return .failure(.tooLong(maximum: 50))
        }

        // Disallow newlines
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return .failure(.containsNewlines)
        }

        // Disallow control characters (except tab)
        let controlCharsWithoutTab = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\t"))
        guard trimmed.rangeOfCharacter(from: controlCharsWithoutTab) == nil else {
            return .failure(.containsControlCharacters)
        }

        return .success(trimmed)
    }

    // MARK: - Bot Naming Rules

    /// Returns true when the provided name matches the auto-generated bot name pattern (e.g. "Bot 1", "bot1", "BOT-3").
    static func isReservedBotName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }

        let lowercase = trimmed.lowercased()
        guard lowercase.hasPrefix("bot") else { return false }

        // Strip typical separators so variations like "bot-1" or "bot 1" are caught
        let suffix = lowercase.dropFirst(3)
        let normalizedSuffix = suffix
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "#", with: "")

        guard !normalizedSuffix.isEmpty else { return false }
        return normalizedSuffix.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
}
