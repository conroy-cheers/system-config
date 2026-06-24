import Foundation

/// Controls SketchyBar visibility by shelling out to the `sketchybar` CLI.
public final class SketchyBarController: BarController {
    private struct AlphaTarget {
        let itemName: String
        let property: String
        let alpha: String
    }

    private let sketchybarPath: String
    private let transitionQueue = DispatchQueue(label: "sketchybar-toggle.bar-transition")
    private let visibleAlpha = "0.5"
    private let hiddenAlpha = "0.0"
    private let minimumTextRestoreAlpha = 0.5
    private let animationDuration = "12"
    private let hideDelay: TimeInterval = 0.32
    private var transitionID = 0
    private var restoreTargets: [AlphaTarget] = []

    public init() {
        sketchybarPath = "@sketchybarPath@"
    }

    public func hide() {
        transitionQueue.async { [self] in
            transitionID += 1
            let currentTransition = transitionID
            let targets = queryAlphaTargets()
            restoreTargets = targets

            run(arguments: animatedArguments(
                barAlpha: hiddenAlpha,
                targets: targets,
                targetAlpha: hiddenAlpha
            ))

            transitionQueue.asyncAfter(deadline: .now() + hideDelay) { [self] in
                guard currentTransition == transitionID else {
                    return
                }

                run(arguments: immediateArguments(
                    hidden: true,
                    barAlpha: visibleAlpha,
                    targets: targets,
                    targetAlpha: nil
                ))
            }
        }
    }

    public func show() {
        transitionQueue.async { [self] in
            transitionID += 1
            let targets = restoreTargets.isEmpty ? queryAlphaTargets() : restoreTargets

            run(arguments: immediateArguments(
                hidden: false,
                barAlpha: hiddenAlpha,
                targets: targets,
                targetAlpha: hiddenAlpha
            ))

            run(arguments: animatedArguments(
                barAlpha: visibleAlpha,
                targets: targets,
                targetAlpha: nil
            ))

            let currentTransition = transitionID
            transitionQueue.asyncAfter(deadline: .now() + hideDelay) { [self] in
                guard currentTransition == transitionID else {
                    return
                }

                run(arguments: ["--trigger", "space_windows_change"])
            }
        }
    }

    private func immediateArguments(
        hidden: Bool,
        barAlpha: String,
        targets: [AlphaTarget],
        targetAlpha: String?
    ) -> [String] {
        var arguments = [
            "--bar",
            "hidden=\(hidden ? "on" : "off")",
            "color.alpha=\(barAlpha)",
            "y_offset=0",
        ]
        arguments.append(contentsOf: alphaArguments(targets: targets, targetAlpha: targetAlpha))
        return arguments
    }

    private func animatedArguments(
        barAlpha: String,
        targets: [AlphaTarget],
        targetAlpha: String?
    ) -> [String] {
        var arguments = [
            "--animate", "sin", animationDuration,
            "--bar",
            "color.alpha=\(barAlpha)",
            "y_offset=0",
        ]
        arguments.append(contentsOf: alphaArguments(targets: targets, targetAlpha: targetAlpha))
        return arguments
    }

    private func alphaArguments(targets: [AlphaTarget], targetAlpha: String?) -> [String] {
        var arguments: [String] = []
        for target in targets {
            arguments.append(contentsOf: [
                "--set",
                target.itemName,
                "\(target.property).alpha=\(targetAlpha ?? target.alpha)",
            ])
        }
        return arguments
    }

    private func queryAlphaTargets() -> [AlphaTarget] {
        guard
            let bar = queryJSONObject(arguments: ["--query", "bar"]),
            let itemNames = bar["items"] as? [String]
        else {
            return []
        }

        var arguments: [String] = []
        for itemName in itemNames {
            arguments.append(contentsOf: ["--query", itemName])
        }

        let objects = queryJSONObjects(arguments: arguments)
        var seen = Set<String>()
        var targets: [AlphaTarget] = []

        for object in objects {
            guard let itemName = object["name"] as? String else {
                continue
            }

            collectTargets(from: object, itemName: itemName, into: &targets, seen: &seen)
        }

        return targets
    }

    private func collectTargets(
        from object: [String: Any],
        itemName: String,
        into targets: inout [AlphaTarget],
        seen: inout Set<String>
    ) {
        addBackgroundTargets(
            object,
            itemName: itemName,
            objectPath: ["geometry", "background"],
            propertyPrefix: "background",
            targets: &targets,
            seen: &seen
        )

        addTextTargets(
            object,
            itemName: itemName,
            domain: "icon",
            targets: &targets,
            seen: &seen
        )

        addTextTargets(
            object,
            itemName: itemName,
            domain: "label",
            targets: &targets,
            seen: &seen
        )

        if dictionary(object, at: ["graph"]) != nil {
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: ["graph", "color"],
                property: "graph.color",
                targets: &targets,
                seen: &seen
            )
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: ["graph", "fill_color"],
                property: "graph.fill_color",
                targets: &targets,
                seen: &seen
            )
        }

        if string(object, at: ["popup", "drawing"]) == "on" {
            addBackgroundTargets(
                object,
                itemName: itemName,
                objectPath: ["popup", "background"],
                propertyPrefix: "popup.background",
                targets: &targets,
                seen: &seen
            )
        }

        if string(object, at: ["slider", "knob", "drawing"]) == "on" {
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: ["slider", "knob", "color"],
                property: "slider.knob.color",
                targets: &targets,
                seen: &seen
            )

            if string(object, at: ["slider", "knob", "highlight"]) == "on" {
                addTargetIfVisible(
                    object,
                    itemName: itemName,
                    colorPath: ["slider", "knob", "highlight_color"],
                    property: "slider.knob.highlight_color",
                    targets: &targets,
                    seen: &seen
                )
            }

            addBackgroundTargets(
                object,
                itemName: itemName,
                objectPath: ["slider", "knob", "background"],
                propertyPrefix: "slider.knob.background",
                targets: &targets,
                seen: &seen
            )
        }
    }

    private func addTextTargets(
        _ object: [String: Any],
        itemName: String,
        domain: String,
        targets: inout [AlphaTarget],
        seen: inout Set<String>
    ) {
        guard string(object, at: [domain, "drawing"]) == "on" else {
            return
        }

        if (string(object, at: [domain, "value"]) ?? "").isEmpty == false {
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: [domain, "color"],
                property: "\(domain).color",
                targets: &targets,
                seen: &seen
            )
        }

        if string(object, at: [domain, "highlight"]) == "on" {
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: [domain, "highlight_color"],
                property: "\(domain).highlight_color",
                targets: &targets,
                seen: &seen
            )
        }

        addBackgroundTargets(
            object,
            itemName: itemName,
            objectPath: [domain, "background"],
            propertyPrefix: "\(domain).background",
            targets: &targets,
            seen: &seen
        )

        if string(object, at: [domain, "shadow", "drawing"]) == "on" {
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: [domain, "shadow", "color"],
                property: "\(domain).shadow.color",
                targets: &targets,
                seen: &seen
            )
        }
    }

    private func addBackgroundTargets(
        _ object: [String: Any],
        itemName: String,
        objectPath: [String],
        propertyPrefix: String,
        targets: inout [AlphaTarget],
        seen: inout Set<String>
    ) {
        guard string(object, at: objectPath + ["drawing"]) == "on" else {
            return
        }

        addTargetIfVisible(
            object,
            itemName: itemName,
            colorPath: objectPath + ["color"],
            property: "\(propertyPrefix).color",
            targets: &targets,
            seen: &seen
        )

        if int(object, at: objectPath + ["border_width"]) > 0 {
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: objectPath + ["border_color"],
                property: "\(propertyPrefix).border_color",
                targets: &targets,
                seen: &seen
            )
        }

        if string(object, at: objectPath + ["shadow", "drawing"]) == "on" {
            addTargetIfVisible(
                object,
                itemName: itemName,
                colorPath: objectPath + ["shadow", "color"],
                property: "\(propertyPrefix).shadow.color",
                targets: &targets,
                seen: &seen
            )
        }
    }

    private func addTargetIfVisible(
        _ object: [String: Any],
        itemName: String,
        colorPath: [String],
        property: String,
        targets: inout [AlphaTarget],
        seen: inout Set<String>
    ) {
        guard
            let color = string(object, at: colorPath),
            let alpha = alphaString(from: color),
            alpha != "0.000"
        else {
            return
        }

        let key = "\(itemName):\(property)"
        guard seen.insert(key).inserted else {
            return
        }

        targets.append(AlphaTarget(
            itemName: itemName,
            property: property,
            alpha: restoreAlpha(for: property, queriedAlpha: alpha)
        ))
    }

    private func restoreAlpha(for property: String, queriedAlpha: String) -> String {
        guard
            isTextColorProperty(property),
            let alpha = Double(queriedAlpha),
            alpha < minimumTextRestoreAlpha
        else {
            return queriedAlpha
        }

        // SketchyBar can be queried mid-animation; do not preserve that faded
        // text alpha as the next visible state.
        return "1.000"
    }

    private func isTextColorProperty(_ property: String) -> Bool {
        (property.hasPrefix("icon.") || property.hasPrefix("label."))
            && property.contains("color")
            && !property.contains("background")
    }

    private func queryJSONObject(arguments: [String]) -> [String: Any]? {
        queryJSONObjects(arguments: arguments).first
    }

    private func queryJSONObjects(arguments: [String]) -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sketchybarPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        return Self.parseJSONObjects(from: data)
    }

    private static func parseJSONObjects(from data: Data) -> [[String: Any]] {
        let bytes = [UInt8](data)
        var index = 0
        var objects: [[String: Any]] = []

        while index < bytes.count {
            while index < bytes.count && Self.isWhitespace(bytes[index]) {
                index += 1
            }

            guard index < bytes.count && bytes[index] == UInt8(ascii: "{") else {
                break
            }

            let start = index
            var depth = 0
            var inString = false
            var escaped = false

            while index < bytes.count {
                let byte = bytes[index]

                if inString {
                    if escaped {
                        escaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        escaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        inString = false
                    }
                } else if byte == UInt8(ascii: "\"") {
                    inString = true
                } else if byte == UInt8(ascii: "{") {
                    depth += 1
                } else if byte == UInt8(ascii: "}") {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        let objectData = data.subdata(in: start..<index)
                        if let object = try? JSONSerialization.jsonObject(with: objectData) as? [String: Any] {
                            objects.append(object)
                        }
                        break
                    }
                }

                index += 1
            }
        }

        return objects
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ")
            || byte == UInt8(ascii: "\n")
            || byte == UInt8(ascii: "\r")
            || byte == UInt8(ascii: "\t")
    }

    private func dictionary(_ object: [String: Any], at path: [String]) -> [String: Any]? {
        var current: Any = object
        for component in path {
            guard let dictionary = current as? [String: Any], let next = dictionary[component] else {
                return nil
            }
            current = next
        }
        return current as? [String: Any]
    }

    private func string(_ object: [String: Any], at path: [String]) -> String? {
        var current: Any = object
        for component in path {
            guard let dictionary = current as? [String: Any], let next = dictionary[component] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    private func int(_ object: [String: Any], at path: [String]) -> Int {
        var current: Any = object
        for component in path {
            guard let dictionary = current as? [String: Any], let next = dictionary[component] else {
                return 0
            }
            current = next
        }

        if let value = current as? Int {
            return value
        }

        if let value = current as? Double {
            return Int(value)
        }

        return 0
    }

    private func alphaString(from color: String) -> String? {
        let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("0x") else {
            return nil
        }

        let hex = String(trimmed.dropFirst(2))
        let alphaByte: UInt8

        switch hex.count {
        case 0:
            return nil
        case 1...6:
            guard UInt32(hex, radix: 16) != 0 else {
                alphaByte = 0
                break
            }
            alphaByte = 255
        default:
            let alphaHex = String(hex.prefix(2))
            guard let parsed = UInt8(alphaHex, radix: 16) else {
                return nil
            }
            alphaByte = parsed
        }

        return String(format: "%.3f", Double(alphaByte) / 255.0)
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

}
