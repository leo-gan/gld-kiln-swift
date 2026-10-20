/// Decode or encode failure. `code` matches the wire specification.
public struct KilnError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Code: String, Sendable, Equatable {
        case FRAME
        case LIMIT
        case EOF
        case TYPE
        case UTF8
        case TRAILING
        case SCHEMA
    }

    public var code: Code
    public var offset: Int

    public init(_ code: Code, offset: Int = 0) {
        self.code = code
        self.offset = offset
    }

    public var description: String { code.rawValue }
}
