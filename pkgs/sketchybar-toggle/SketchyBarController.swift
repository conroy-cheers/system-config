import Foundation

/// Controls SketchyBar visibility by shelling out to the `sketchybar` CLI.
public final class SketchyBarController: BarController {
    private let sketchybarPath: String
    private var visibleBarAlpha: Double

    public init() {
        sketchybarPath = "@sketchybarPath@"
        visibleBarAlpha = Self.queryBarAlpha(sketchybarPath: sketchybarPath) ?? 1.0
    }

    public func hide() {
        if let alpha = Self.queryBarAlpha(sketchybarPath: sketchybarPath) {
            visibleBarAlpha = alpha
        }

        runAsync(arguments: [
            "--animate", "sin", "8",
            "--bar",
            "color.alpha=0.1",
            "y_offset=-8",
        ])

        Thread.sleep(forTimeInterval: 0.12)

        run(arguments: ["--bar", "hidden=on", "y_offset=0"])
    }

    public func show() {
        let alphaString = String(format: "%.3f", visibleBarAlpha)

        run(arguments: [
            "--bar",
            "hidden=off",
            "y_offset=-50",
            "color.alpha=0.1",
        ])

        runAsync(arguments: [
            "--animate", "sin", "12",
            "--bar",
            "y_offset=0",
            "color.alpha=\(alphaString)",
        ])
    }

    private func run(arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sketchybarPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
        }
    }

    private func runAsync(arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sketchybarPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
        }
    }

    private static func queryBarAlpha(sketchybarPath: String) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sketchybarPath)
        process.arguments = ["--query", "bar"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let output = String(data: data, encoding: .utf8),
            let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
            let color = json["color"] as? String
        else {
            return nil
        }

        return parseAlpha(from: color)
    }

    private static func parseAlpha(from argb: String) -> Double? {
        let trimmed = argb.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("0x"), trimmed.count == 10 else {
            return nil
        }

        let alphaHex = String(trimmed.dropFirst(2).prefix(2))
        guard let alphaByte = UInt8(alphaHex, radix: 16) else {
            return nil
        }

        return Double(alphaByte) / 255.0
    }
}
