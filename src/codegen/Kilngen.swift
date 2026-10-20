import Foundation

@main
struct Kilngen {
    static func main() {
        do {
            try run()
        } catch {
            fail("gld-kilngen-swift: \(error)")
        }
    }

    static func run() throws {
        var schema = ""
        var outDir = ""
        var output = ""
        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--schema":
                schema = try take(&args)
            case "--out":
                outDir = try take(&args)
            case "-o", "--output":
                output = try take(&args)
            case "-h", "--help":
                fail("usage: gld-kilngen-swift --schema FILE --out DIR", code: 0)
            default:
                if schema.isEmpty {
                    schema = arg
                } else {
                    throw KilnGenError("usage: gld-kilngen-swift --schema FILE --out DIR")
                }
            }
        }
        if schema.isEmpty || (outDir.isEmpty && output.isEmpty) {
            throw KilnGenError("usage: gld-kilngen-swift --schema FILE --out DIR")
        }
        let text = try String(contentsOfFile: schema, encoding: .utf8)
        let (name, source) = try emitSwift(text)
        if !output.isEmpty {
            try source.write(toFile: output, atomically: true, encoding: .utf8)
            return
        }
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".swift").path
        try source.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func take(_ args: inout [String]) throws -> String {
        guard !args.isEmpty else { throw KilnGenError("missing argument") }
        return args.removeFirst()
    }

    static func fail(_ text: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data((text + "\n").utf8))
        exit(code)
    }
}

struct KilnGenError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
