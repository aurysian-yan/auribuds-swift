#!/usr/bin/env swift
import AppKit
import Foundation
import Vision

struct ImageItem {
    let url: URL
    let fileName: String
    let device: String
    let color: String
    let sequence: Int
    let feature: VNFeaturePrintObservation
}

struct StateRow: Codable {
    let device: String
    let color: String
    let state: String
    let imageCount: Int
    let files: [String]
}

struct Options {
    var inputDir = "output-images"
    var outputDir = "output-images-stated"
    var clusters = 4
    var tableCsv = "device_color_state_map.csv"
    var tableJson = "device_color_state_map.json"
    var overrides = "state_overrides.json"
}

enum ScriptError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidImageName(String)
    case noImages
    case noFeature(String)

    var description: String {
        switch self {
        case .missingValue(let key):
            return "缺少参数值: \(key)"
        case .invalidImageName(let name):
            return "文件名不符合格式: \(name)"
        case .noImages:
            return "没有找到可处理的图片"
        case .noFeature(let name):
            return "无法提取图像特征: \(name)"
        }
    }
}

func parseOptions() throws -> Options {
    var options = Options()
    var index = 1
    let args = CommandLine.arguments

    while index < args.count {
        let key = args[index]
        func value() throws -> String {
            guard index + 1 < args.count else {
                throw ScriptError.missingValue(key)
            }
            index += 1
            return args[index]
        }

        switch key {
        case "--input-dir":
            options.inputDir = try value()
        case "--output-dir":
            options.outputDir = try value()
        case "--clusters":
            options.clusters = max(1, Int(try value()) ?? options.clusters)
        case "--table-csv":
            options.tableCsv = try value()
        case "--table-json":
            options.tableJson = try value()
        case "--overrides":
            options.overrides = try value()
        default:
            break
        }
        index += 1
    }

    return options
}

func imageFiles(in directory: URL) throws -> [URL] {
    let supported = Set(["png", "jpg", "jpeg", "webp", "gif"])
    let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    return files
        .filter { supported.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

func parseImageName(_ name: String) throws -> (device: String, color: String, sequence: Int) {
    let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    let parts = base.components(separatedBy: "__")
    guard parts.count >= 2 else {
        throw ScriptError.invalidImageName(name)
    }

    let device = parts[0]
    let colorAndSequence = parts[1]
    let regex = try NSRegularExpression(pattern: #"^(.*)_(\d+)$"#)
    let range = NSRange(colorAndSequence.startIndex..<colorAndSequence.endIndex, in: colorAndSequence)
    guard
        let match = regex.firstMatch(in: colorAndSequence, range: range),
        let colorRange = Range(match.range(at: 1), in: colorAndSequence),
        let sequenceRange = Range(match.range(at: 2), in: colorAndSequence),
        let sequence = Int(colorAndSequence[sequenceRange])
    else {
        throw ScriptError.invalidImageName(name)
    }

    return (device, String(colorAndSequence[colorRange]), sequence)
}

func featurePrint(for url: URL) throws -> VNFeaturePrintObservation {
    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(url: url, options: [:])
    try handler.perform([request])

    guard let feature = request.results?.first as? VNFeaturePrintObservation else {
        throw ScriptError.noFeature(url.lastPathComponent)
    }
    return feature
}

func distance(_ left: VNFeaturePrintObservation, _ right: VNFeaturePrintObservation) -> Float {
    var result: Float = 0
    do {
        try left.computeDistance(&result, to: right)
    } catch {
        return Float.greatestFiniteMagnitude
    }
    return result
}

func distanceMatrix(_ items: [ImageItem]) -> [[Float]] {
    var matrix = Array(repeating: Array(repeating: Float(0), count: items.count), count: items.count)
    for i in 0..<items.count {
        for j in (i + 1)..<items.count {
            let value = distance(items[i].feature, items[j].feature)
            matrix[i][j] = value
            matrix[j][i] = value
        }
    }
    return matrix
}

func initialMedoids(matrix: [[Float]], count: Int) -> [Int] {
    guard !matrix.isEmpty else { return [] }
    var medoids = [0]
    while medoids.count < min(count, matrix.count) {
        var bestIndex = 0
        var bestDistance: Float = -1
        for index in 0..<matrix.count where !medoids.contains(index) {
            let nearest = medoids.map { matrix[index][$0] }.min() ?? 0
            if nearest > bestDistance {
                bestDistance = nearest
                bestIndex = index
            }
        }
        medoids.append(bestIndex)
    }
    return medoids
}

func clusterItems(matrix: [[Float]], clusterCount: Int) -> [Int] {
    let count = matrix.count
    var medoids = initialMedoids(matrix: matrix, count: clusterCount)
    var assignments = Array(repeating: 0, count: count)

    for _ in 0..<12 {
        for itemIndex in 0..<count {
            var bestCluster = 0
            var bestDistance = Float.greatestFiniteMagnitude
            for (clusterIndex, medoidIndex) in medoids.enumerated() {
                let value = matrix[itemIndex][medoidIndex]
                if value < bestDistance {
                    bestDistance = value
                    bestCluster = clusterIndex
                }
            }
            assignments[itemIndex] = bestCluster
        }

        var nextMedoids = medoids
        for clusterIndex in 0..<medoids.count {
            let members = (0..<count).filter { assignments[$0] == clusterIndex }
            guard !members.isEmpty else { continue }

            var bestMember = members[0]
            var bestTotal = Float.greatestFiniteMagnitude
            for candidate in members {
                let total = members.reduce(Float(0)) { $0 + matrix[candidate][$1] }
                if total < bestTotal {
                    bestTotal = total
                    bestMember = candidate
                }
            }
            nextMedoids[clusterIndex] = bestMember
        }

        if nextMedoids == medoids {
            break
        }
        medoids = nextMedoids
    }

    return assignments
}

func orderedStateNames(items: [ImageItem], assignments: [Int]) -> [Int: String] {
    let defaultNames = ["open_case", "earbuds_with_case", "closed_case", "earbuds_pair"]
    let clusters = Set(assignments).sorted()
    let ordered = clusters.sorted { left, right in
        let leftItems = items.indices.filter { assignments[$0] == left }.map { items[$0] }
        let rightItems = items.indices.filter { assignments[$0] == right }.map { items[$0] }
        let leftAverage = Double(leftItems.map(\.sequence).reduce(0, +)) / Double(max(leftItems.count, 1))
        let rightAverage = Double(rightItems.map(\.sequence).reduce(0, +)) / Double(max(rightItems.count, 1))
        if leftAverage == rightAverage {
            return left < right
        }
        return leftAverage < rightAverage
    }

    var names: [Int: String] = [:]
    for (index, cluster) in ordered.enumerated() {
        if index < defaultNames.count {
            names[cluster] = defaultNames[index]
        } else {
            names[cluster] = "state_\(String(format: "%02d", index + 1))"
        }
    }
    return names
}

func clearImages(in directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let files = try imageFiles(in: directory)
    for file in files {
        try FileManager.default.removeItem(at: file)
    }
}

func writeCsv(rows: [StateRow], to url: URL) throws {
    var output = "device,color,state,imageCount,files\n"
    for row in rows {
        let files = row.files.joined(separator: "|")
        output += "\(csv(row.device)),\(csv(row.color)),\(csv(row.state)),\(row.imageCount),\(csv(files))\n"
    }
    try output.write(to: url, atomically: true, encoding: .utf8)
}

func csv(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}

func loadOverrides(path: String) throws -> [String: String] {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        return [:]
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode([String: String].self, from: data)
}

func main() throws {
    let options = try parseOptions()
    let inputDir = URL(fileURLWithPath: options.inputDir)
    let outputDir = URL(fileURLWithPath: options.outputDir)
    let overrides = try loadOverrides(path: options.overrides)
    let files = try imageFiles(in: inputDir)
    guard !files.isEmpty else {
        throw ScriptError.noImages
    }

    var items: [ImageItem] = []
    for file in files {
        let parsed = try parseImageName(file.lastPathComponent)
        let feature = try featurePrint(for: file)
        items.append(
            ImageItem(
                url: file,
                fileName: file.lastPathComponent,
                device: parsed.device,
                color: parsed.color,
                sequence: parsed.sequence,
                feature: feature
            )
        )
    }

    let matrix = distanceMatrix(items)
    let assignments = clusterItems(matrix: matrix, clusterCount: min(options.clusters, items.count))
    let stateNames = orderedStateNames(items: items, assignments: assignments)

    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    try clearImages(in: outputDir)

    var counters: [String: Int] = [:]
    var groups: [String: StateRow] = [:]
    var outputFilesByGroup: [String: [String]] = [:]

    for index in items.indices {
        let item = items[index]
        let state = overrides[item.fileName] ?? stateNames[assignments[index]] ?? "state_unknown"
        let groupKey = "\(item.device)__\(item.color)__\(state)"
        counters[groupKey, default: 0] += 1
        let outputName = "\(item.device)__\(item.color)__\(state)_\(String(format: "%03d", counters[groupKey]!)).\(item.url.pathExtension.lowercased())"
        let target = outputDir.appendingPathComponent(outputName)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: item.url, to: target)
        outputFilesByGroup[groupKey, default: []].append(outputName)
        groups[groupKey] = StateRow(
            device: item.device,
            color: item.color,
            state: state,
            imageCount: outputFilesByGroup[groupKey]?.count ?? 0,
            files: outputFilesByGroup[groupKey] ?? []
        )
    }

    let rows = groups.keys.sorted().compactMap { key -> StateRow? in
        guard let row = groups[key] else { return nil }
        let files = outputFilesByGroup[key] ?? []
        return StateRow(device: row.device, color: row.color, state: row.state, imageCount: files.count, files: files)
    }

    let csvUrl = outputDir.appendingPathComponent(options.tableCsv)
    let jsonUrl = outputDir.appendingPathComponent(options.tableJson)
    try writeCsv(rows: rows, to: csvUrl)
    let jsonData = try JSONEncoder().encode(rows)
    try jsonData.write(to: jsonUrl)

    print("处理图片: \(items.count)")
    print("状态数量: \(Set(assignments).count)")
    print("输出目录: \(options.outputDir)")
    print("状态表: \(csvUrl.lastPathComponent), \(jsonUrl.lastPathComponent)")
}

do {
    try main()
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
