#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct Options {
    var inputDir = "output-images-stated"
    var outputDir = "output-images-trimmed"
    var alphaThreshold: UInt8 = 8
    var backgroundTolerance: UInt8 = 12
    var padding = 0
    var dedupeThreshold: Float = 0.16
    var reportJson = "trim_report.json"
    var reportCsv = "trim_report.csv"
}

struct ParsedName {
    let device: String
    let color: String
    let state: String
}

struct PixelImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]
}

struct RGB {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

struct BoundsInfo {
    let rect: CGRect
    let background: RGB?
    let backgroundTolerance: UInt8
}

struct ImageRecord {
    let url: URL
    let parsed: ParsedName
    let image: PixelImage
    let bounds: BoundsInfo
    let baseSide: Int
    let feature: VNFeaturePrintObservation
}

struct TrimReport: Codable {
    let file: String
    let device: String
    let color: String
    let state: String
    let sourceWidth: Int
    let sourceHeight: Int
    let contentX: Int
    let contentY: Int
    let contentWidth: Int
    let contentHeight: Int
    let outputSize: Int
    let duplicateOf: String?
}

struct StateRow: Codable {
    let device: String
    let color: String
    let state: String
    let imageCount: Int
    let files: [String]
}

enum ScriptError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidName(String)
    case noImages
    case imageLoadFailed(String)
    case bitmapFailed(String)
    case encodeFailed(String)
    case emptyAlpha(String)

    var description: String {
        switch self {
        case .missingValue(let key):
            return "缺少参数值: \(key)"
        case .invalidName(let name):
            return "文件名不符合格式: \(name)"
        case .noImages:
            return "没有找到可处理的图片"
        case .imageLoadFailed(let name):
            return "无法读取图片: \(name)"
        case .bitmapFailed(let name):
            return "无法转换像素: \(name)"
        case .encodeFailed(let name):
            return "无法写入 PNG: \(name)"
        case .emptyAlpha(let name):
            return "图片没有可见 Alpha 内容: \(name)"
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
        case "--alpha-threshold":
            options.alphaThreshold = UInt8(clamping: Int(try value()) ?? Int(options.alphaThreshold))
        case "--background-tolerance":
            options.backgroundTolerance = UInt8(clamping: Int(try value()) ?? Int(options.backgroundTolerance))
        case "--padding":
            options.padding = max(0, Int(try value()) ?? options.padding)
        case "--dedupe-threshold":
            options.dedupeThreshold = Float(try value()) ?? options.dedupeThreshold
        case "--report-json":
            options.reportJson = try value()
        case "--report-csv":
            options.reportCsv = try value()
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

func parseName(_ fileName: String) throws -> ParsedName {
    let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    let parts = base.components(separatedBy: "__")
    guard parts.count == 3 else {
        throw ScriptError.invalidName(fileName)
    }

    let stateAndIndex = parts[2]
    let regex = try NSRegularExpression(pattern: #"^(.*)_\d+$"#)
    let range = NSRange(stateAndIndex.startIndex..<stateAndIndex.endIndex, in: stateAndIndex)
    guard
        let match = regex.firstMatch(in: stateAndIndex, range: range),
        let stateRange = Range(match.range(at: 1), in: stateAndIndex)
    else {
        throw ScriptError.invalidName(fileName)
    }

    return ParsedName(device: parts[0], color: parts[1], state: String(stateAndIndex[stateRange]))
}

func loadPixels(from url: URL) throws -> PixelImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ScriptError.imageLoadFailed(url.lastPathComponent)
    }

    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = Array(repeating: UInt8(0), count: height * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    let ok = pixels.withUnsafeMutableBytes { pointer -> Bool in
        guard
            let baseAddress = pointer.baseAddress,
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            return false
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    guard ok else {
        throw ScriptError.bitmapFailed(url.lastPathComponent)
    }

    return PixelImage(width: width, height: height, pixels: pixels)
}

func pixelRGB(_ image: PixelImage, x: Int, y: Int) -> RGB {
    let index = ((y * image.width) + x) * 4
    return RGB(r: image.pixels[index], g: image.pixels[index + 1], b: image.pixels[index + 2])
}

func pixelAlpha(_ image: PixelImage, x: Int, y: Int) -> UInt8 {
    let index = ((y * image.width) + x) * 4 + 3
    return image.pixels[index]
}

func colorDistance(_ left: RGB, _ right: RGB) -> UInt8 {
    let red = abs(Int(left.r) - Int(right.r))
    let green = abs(Int(left.g) - Int(right.g))
    let blue = abs(Int(left.b) - Int(right.b))
    return UInt8(clamping: max(red, max(green, blue)))
}

func averageBackgroundColor(of image: PixelImage, threshold: UInt8) -> RGB? {
    let sampleSize = min(24, image.width, image.height)
    let starts = [
        (0, 0),
        (image.width - sampleSize, 0),
        (0, image.height - sampleSize),
        (image.width - sampleSize, image.height - sampleSize),
    ]
    var colors: [RGB] = []

    for start in starts {
        var red = 0
        var green = 0
        var blue = 0
        var count = 0

        for y in start.1..<(start.1 + sampleSize) {
            for x in start.0..<(start.0 + sampleSize) where pixelAlpha(image, x: x, y: y) > threshold {
                let color = pixelRGB(image, x: x, y: y)
                red += Int(color.r)
                green += Int(color.g)
                blue += Int(color.b)
                count += 1
            }
        }

        guard count > 0 else {
            return nil
        }

        colors.append(
            RGB(
                r: UInt8(clamping: red / count),
                g: UInt8(clamping: green / count),
                b: UInt8(clamping: blue / count)
            )
        )
    }

    let red = colors.map { Int($0.r) }.reduce(0, +) / colors.count
    let green = colors.map { Int($0.g) }.reduce(0, +) / colors.count
    let blue = colors.map { Int($0.b) }.reduce(0, +) / colors.count
    let average = RGB(r: UInt8(clamping: red), g: UInt8(clamping: green), b: UInt8(clamping: blue))
    let maxDistance = colors.map { colorDistance($0, average) }.max() ?? 0
    guard maxDistance <= 6 else {
        return nil
    }
    return average
}

func boundsByMask(image: PixelImage, fileName: String, isContent: (Int, Int) -> Bool) throws -> CGRect {
    var minX = image.width
    var minY = image.height
    var maxX = -1
    var maxY = -1

    for y in 0..<image.height {
        for x in 0..<image.width {
            if isContent(x, y) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard maxX >= minX && maxY >= minY else {
        throw ScriptError.emptyAlpha(fileName)
    }

    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func contentBounds(of image: PixelImage, alphaThreshold: UInt8, backgroundTolerance: UInt8, fileName: String) throws -> BoundsInfo {
    let alphaRect = try boundsByMask(image: image, fileName: fileName) { x, y in
        pixelAlpha(image, x: x, y: y) > alphaThreshold
    }

    let alphaCoversCanvas =
        Int(alphaRect.minX) == 0 &&
        Int(alphaRect.minY) == 0 &&
        Int(alphaRect.width) == image.width &&
        Int(alphaRect.height) == image.height

    guard alphaCoversCanvas, let background = averageBackgroundColor(of: image, threshold: alphaThreshold) else {
        return BoundsInfo(rect: alphaRect, background: nil, backgroundTolerance: backgroundTolerance)
    }

    let colorRect = try boundsByMask(image: image, fileName: fileName) { x, y in
        guard pixelAlpha(image, x: x, y: y) > alphaThreshold else {
            return false
        }
        return colorDistance(pixelRGB(image, x: x, y: y), background) > backgroundTolerance
    }

    return BoundsInfo(rect: colorRect, background: background, backgroundTolerance: backgroundTolerance)
}

func groupKey(_ parsed: ParsedName) -> String {
    "\(parsed.device)__\(parsed.state)"
}

func duplicateGroupKey(_ parsed: ParsedName) -> String {
    "\(parsed.device)__\(parsed.color)__\(parsed.state)"
}

func featurePrint(for url: URL) throws -> VNFeaturePrintObservation {
    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(url: url, options: [:])
    try handler.perform([request])

    guard let feature = request.results?.first as? VNFeaturePrintObservation else {
        throw ScriptError.imageLoadFailed(url.lastPathComponent)
    }
    return feature
}

func featureDistance(_ left: VNFeaturePrintObservation, _ right: VNFeaturePrintObservation) -> Float {
    var result: Float = 0
    do {
        try left.computeDistance(&result, to: right)
    } catch {
        return Float.greatestFiniteMagnitude
    }
    return result
}

func deduplicate(records: [ImageRecord], threshold: Float) -> (kept: [ImageRecord], duplicates: [String: String]) {
    var kept: [ImageRecord] = []
    var duplicates: [String: String] = [:]
    var groups: [String: [ImageRecord]] = [:]

    for record in records {
        let key = duplicateGroupKey(record.parsed)
        var duplicateOf: String?
        for existing in groups[key] ?? [] {
            if featureDistance(record.feature, existing.feature) <= threshold {
                duplicateOf = existing.url.lastPathComponent
                break
            }
        }

        if let duplicateOf {
            duplicates[record.url.lastPathComponent] = duplicateOf
        } else {
            groups[key, default: []].append(record)
            kept.append(record)
        }
    }

    return (kept, duplicates)
}

func pixelFromRecord(_ record: ImageRecord, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    guard x >= 0 && x < record.image.width && y >= 0 && y < record.image.height else {
        return (0, 0, 0, 0)
    }

    let index = ((y * record.image.width) + x) * 4
    let red = record.image.pixels[index]
    let green = record.image.pixels[index + 1]
    let blue = record.image.pixels[index + 2]
    let alpha = record.image.pixels[index + 3]

    if let background = record.bounds.background {
        let sourceColor = RGB(r: red, g: green, b: blue)
        if colorDistance(sourceColor, background) <= record.bounds.backgroundTolerance {
            return (0, 0, 0, 0)
        }
    }

    return (red, green, blue, alpha)
}

func tightSquare(record: ImageRecord) -> PixelImage {
    let side = max(1, record.baseSide)
    var output = PixelImage(
        width: side,
        height: side,
        pixels: Array(repeating: UInt8(0), count: side * side * 4)
    )

    let centerX = Int(record.bounds.rect.midX.rounded(.toNearestOrAwayFromZero))
    let centerY = Int(record.bounds.rect.midY.rounded(.toNearestOrAwayFromZero))
    let cropX = centerX - side / 2
    let cropY = centerY - side / 2

    for y in 0..<side {
        for x in 0..<side {
            let pixel = pixelFromRecord(record, x: cropX + x, y: cropY + y)
            let outputIndex = ((y * side) + x) * 4
            output.pixels[outputIndex] = pixel.0
            output.pixels[outputIndex + 1] = pixel.1
            output.pixels[outputIndex + 2] = pixel.2
            output.pixels[outputIndex + 3] = pixel.3
        }
    }

    return output
}

func resized(_ image: PixelImage, side: Int) -> PixelImage {
    let outputSide = max(1, side)
    guard image.width != outputSide || image.height != outputSide else {
        return image
    }

    var output = PixelImage(
        width: outputSide,
        height: outputSide,
        pixels: Array(repeating: UInt8(0), count: outputSide * outputSide * 4)
    )

    let scaleX = Double(image.width) / Double(outputSide)
    let scaleY = Double(image.height) / Double(outputSide)

    for y in 0..<outputSide {
        let sourceY = min(image.height - 1, max(0, Int((Double(y) + 0.5) * scaleY)))
        for x in 0..<outputSide {
            let sourceX = min(image.width - 1, max(0, Int((Double(x) + 0.5) * scaleX)))
            let sourceIndex = ((sourceY * image.width) + sourceX) * 4
            let outputIndex = ((y * outputSide) + x) * 4
            output.pixels[outputIndex] = image.pixels[sourceIndex]
            output.pixels[outputIndex + 1] = image.pixels[sourceIndex + 1]
            output.pixels[outputIndex + 2] = image.pixels[sourceIndex + 2]
            output.pixels[outputIndex + 3] = image.pixels[sourceIndex + 3]
        }
    }

    return output
}

func trimToSquare(record: ImageRecord, side: Int) -> PixelImage {
    return resized(tightSquare(record: record), side: side)
}

func legacyTrimToSquare(record: ImageRecord, side: Int) -> PixelImage {
    let outputSide = max(1, side)
    var output = PixelImage(
        width: outputSide,
        height: outputSide,
        pixels: Array(repeating: UInt8(0), count: outputSide * outputSide * 4)
    )

    let centerX = Int(record.bounds.rect.midX.rounded(.toNearestOrAwayFromZero))
    let centerY = Int(record.bounds.rect.midY.rounded(.toNearestOrAwayFromZero))
    let cropX = centerX - outputSide / 2
    let cropY = centerY - outputSide / 2

    for y in 0..<outputSide {
        let sourceY = cropY + y
        guard sourceY >= 0 && sourceY < record.image.height else { continue }

        for x in 0..<outputSide {
            let sourceX = cropX + x
            guard sourceX >= 0 && sourceX < record.image.width else { continue }

            let sourceIndex = ((sourceY * record.image.width) + sourceX) * 4
            let outputIndex = ((y * outputSide) + x) * 4
            if let background = record.bounds.background {
                let sourceColor = RGB(
                    r: record.image.pixels[sourceIndex],
                    g: record.image.pixels[sourceIndex + 1],
                    b: record.image.pixels[sourceIndex + 2]
                )
                if colorDistance(sourceColor, background) <= record.bounds.backgroundTolerance {
                    continue
                }
            }
            output.pixels[outputIndex] = record.image.pixels[sourceIndex]
            output.pixels[outputIndex + 1] = record.image.pixels[sourceIndex + 1]
            output.pixels[outputIndex + 2] = record.image.pixels[sourceIndex + 2]
            output.pixels[outputIndex + 3] = record.image.pixels[sourceIndex + 3]
        }
    }

    return output
}

func writePNG(_ image: PixelImage, to url: URL) throws {
    let bytesPerPixel = 4
    let bytesPerRow = image.width * bytesPerPixel
    let data = Data(image.pixels)

    guard
        let provider = CGDataProvider(data: data as CFData),
        let cgImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw ScriptError.encodeFailed(url.lastPathComponent)
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScriptError.encodeFailed(url.lastPathComponent)
    }
}

func clearImages(in directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for file in try imageFiles(in: directory) {
        try FileManager.default.removeItem(at: file)
    }
}

func csv(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}

func writeReportCsv(_ reports: [TrimReport], to url: URL) throws {
    var output = "file,device,color,state,sourceWidth,sourceHeight,contentX,contentY,contentWidth,contentHeight,outputSize,duplicateOf\n"
    for item in reports {
        output += [
            csv(item.file),
            csv(item.device),
            csv(item.color),
            csv(item.state),
            String(item.sourceWidth),
            String(item.sourceHeight),
            String(item.contentX),
            String(item.contentY),
            String(item.contentWidth),
            String(item.contentHeight),
            String(item.outputSize),
            csv(item.duplicateOf ?? ""),
        ].joined(separator: ",")
        output += "\n"
    }
    try output.write(to: url, atomically: true, encoding: .utf8)
}

func writeStateCsv(rows: [StateRow], to url: URL) throws {
    var output = "device,color,state,imageCount,files\n"
    for row in rows {
        output += [
            csv(row.device),
            csv(row.color),
            csv(row.state),
            String(row.imageCount),
            csv(row.files.joined(separator: "|")),
        ].joined(separator: ",")
        output += "\n"
    }
    try output.write(to: url, atomically: true, encoding: .utf8)
}

func writeStateMap(filesByGroup: [String: [String]], parsedByGroup: [String: ParsedName], outputDir: URL) throws {
    let rows = filesByGroup.keys.sorted().compactMap { key -> StateRow? in
        guard let parsed = parsedByGroup[key] else { return nil }
        let files = filesByGroup[key] ?? []
        return StateRow(device: parsed.device, color: parsed.color, state: parsed.state, imageCount: files.count, files: files)
    }

    try writeStateCsv(rows: rows, to: outputDir.appendingPathComponent("device_color_state_map.csv"))
    let jsonData = try JSONEncoder().encode(rows)
    try jsonData.write(to: outputDir.appendingPathComponent("device_color_state_map.json"))
}

func main() throws {
    let options = try parseOptions()
    let inputDir = URL(fileURLWithPath: options.inputDir)
    let outputDir = URL(fileURLWithPath: options.outputDir)
    let files = try imageFiles(in: inputDir)
    guard !files.isEmpty else {
        throw ScriptError.noImages
    }

    var records: [ImageRecord] = []
    var groupSides: [String: Int] = [:]

    for file in files {
        let parsed = try parseName(file.lastPathComponent)
        let image = try loadPixels(from: file)
        let bounds = try contentBounds(
            of: image,
            alphaThreshold: options.alphaThreshold,
            backgroundTolerance: options.backgroundTolerance,
            fileName: file.lastPathComponent
        )
        let baseSide = Int(max(bounds.rect.width, bounds.rect.height)) + options.padding * 2
        let feature = try featurePrint(for: file)
        let record = ImageRecord(url: file, parsed: parsed, image: image, bounds: bounds, baseSide: baseSide, feature: feature)
        records.append(record)
    }

    let dedupeResult = deduplicate(records: records, threshold: options.dedupeThreshold)
    let keptRecords = dedupeResult.kept

    for record in keptRecords {
        let key = groupKey(record.parsed)
        groupSides[key] = max(groupSides[key] ?? 0, record.baseSide)
    }

    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    try clearImages(in: outputDir)

    var reports: [TrimReport] = []
    var filesByStateGroup: [String: [String]] = [:]
    var parsedByStateGroup: [String: ParsedName] = [:]

    for record in keptRecords {
        let side = groupSides[groupKey(record.parsed)] ?? record.baseSide
        let output = trimToSquare(record: record, side: side)
        let target = outputDir.appendingPathComponent(record.url.lastPathComponent)
        try writePNG(output, to: target)
        let stateGroupKey = "\(record.parsed.device)__\(record.parsed.color)__\(record.parsed.state)"
        filesByStateGroup[stateGroupKey, default: []].append(target.lastPathComponent)
        parsedByStateGroup[stateGroupKey] = record.parsed
        reports.append(
            TrimReport(
                file: target.lastPathComponent,
                device: record.parsed.device,
                color: record.parsed.color,
                state: record.parsed.state,
                sourceWidth: record.image.width,
                sourceHeight: record.image.height,
                contentX: Int(record.bounds.rect.minX),
                contentY: Int(record.bounds.rect.minY),
                contentWidth: Int(record.bounds.rect.width),
                contentHeight: Int(record.bounds.rect.height),
                outputSize: side,
                duplicateOf: nil
            )
        )
    }

    for record in records where dedupeResult.duplicates[record.url.lastPathComponent] != nil {
        reports.append(
            TrimReport(
                file: record.url.lastPathComponent,
                device: record.parsed.device,
                color: record.parsed.color,
                state: record.parsed.state,
                sourceWidth: record.image.width,
                sourceHeight: record.image.height,
                contentX: Int(record.bounds.rect.minX),
                contentY: Int(record.bounds.rect.minY),
                contentWidth: Int(record.bounds.rect.width),
                contentHeight: Int(record.bounds.rect.height),
                outputSize: 0,
                duplicateOf: dedupeResult.duplicates[record.url.lastPathComponent]
            )
        )
    }

    let reportURL = outputDir.appendingPathComponent(options.reportJson)
    let reportData = try JSONEncoder().encode(reports)
    try reportData.write(to: reportURL)
    try writeReportCsv(reports, to: outputDir.appendingPathComponent(options.reportCsv))
    try writeStateMap(filesByGroup: filesByStateGroup, parsedByGroup: parsedByStateGroup, outputDir: outputDir)

    print("处理图片: \(records.count)")
    print("去重后图片: \(keptRecords.count)")
    print("重复图片: \(dedupeResult.duplicates.count)")
    print("分组数量: \(groupSides.count)")
    print("输出目录: \(options.outputDir)")
    print("裁切报告: \(reportURL.lastPathComponent), \(options.reportCsv)")
}

do {
    try main()
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
