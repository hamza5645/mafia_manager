import Foundation

/// Comprehensive input validation for user-provided data
enum InputValidator {

    // MARK: - Validation Errors

    enum ValidationError: LocalizedError {
        case empty
        case tooShort(minimum: Int)
        case tooLong(maximum: Int)
        case invalidCharacters
        case invalidFormat
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
            case .invalidFormat:
                return "Invalid format"
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

    // MARK: - Email Validation

    static func validateEmail(_ email: String) -> Result<String, ValidationError> {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Check not empty
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }

        // Check length (max 320 characters per RFC 5321)
        guard trimmed.count <= 320 else {
            return .failure(.tooLong(maximum: 320))
        }

        // Validate email format
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)

        guard emailPredicate.evaluate(with: trimmed) else {
            return .failure(.invalidFormat)
        }

        return .success(trimmed)
    }

    // MARK: - Display Name Validation

    static func validateDisplayName(_ name: String) -> Result<String, ValidationError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check not empty
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }

        // Check length (1-100 characters)
        guard trimmed.count >= 1 else {
            return .failure(.tooShort(minimum: 1))
        }

        guard trimmed.count <= 100 else {
            return .failure(.tooLong(maximum: 100))
        }

        // Disallow newlines
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return .failure(.containsNewlines)
        }

        // Disallow control characters
        guard trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return .failure(.containsControlCharacters)
        }

        return .success(trimmed)
    }

    // MARK: - Password Validation

    static func validatePassword(_ password: String) -> Result<String, ValidationError> {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check not empty
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }

        // Minimum 6 characters (Supabase default)
        guard trimmed.count >= 6 else {
            return .failure(.tooShort(minimum: 6))
        }

        // Maximum 72 characters (bcrypt limit)
        guard trimmed.count <= 72 else {
            return .failure(.tooLong(maximum: 72))
        }

        return .success(trimmed)
    }

    // MARK: - Notes Validation

    static func validateNote(_ note: String) -> Result<String, ValidationError> {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty is OK for notes
        guard !trimmed.isEmpty else {
            return .success("")
        }

        // Check length (max 500 characters)
        guard trimmed.count <= 500 else {
            return .failure(.tooLong(maximum: 500))
        }

        // Disallow control characters (newlines are OK)
        let controlCharsWithoutNewlines = CharacterSet.controlCharacters.subtracting(.newlines)
        guard trimmed.rangeOfCharacter(from: controlCharsWithoutNewlines) == nil else {
            return .failure(.containsControlCharacters)
        }

        return .success(trimmed)
    }

    // MARK: - Group Name Validation

    static func validateGroupName(_ name: String) -> Result<String, ValidationError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check not empty
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }

        // Check length (1-100 characters)
        guard trimmed.count >= 1 else {
            return .failure(.tooShort(minimum: 1))
        }

        guard trimmed.count <= 100 else {
            return .failure(.tooLong(maximum: 100))
        }

        // Disallow newlines
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return .failure(.containsNewlines)
        }

        // Disallow control characters
        guard trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return .failure(.containsControlCharacters)
        }

        return .success(trimmed)
    }

    // MARK: - Config Name Validation

    static func validateConfigName(_ name: String) -> Result<String, ValidationError> {
        // Same rules as group name
        return validateGroupName(name)
    }
}
