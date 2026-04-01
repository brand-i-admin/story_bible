#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Config {
    var paths: [String] = []
    var contentRatio: Double = 0.90
    var whiteThreshold: UInt8 = 248
    var verbose = false
}

enum ScriptError: Error, CustomStringConvertible {
    case usage(String)
    case loadFailed(String)
    case noForeground(String)
    case createContextFailed
    case writeFailed(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .loadFailed(let path):
            return "이미지를 열 수 없습니다: \(path)"
        case .noForeground(let path):
            return "전경 영역을 찾지 못했습니다: \(path)"
        case .createContextFailed:
            return "비트맵 컨텍스트를 만들지 못했습니다."
        case .writeFailed(let path):
            return "PNG 저장에 실패했습니다: \(path)"
        }
    }
}

func parseArgs() throws -> Config {
    var config = Config()
    var index = 1
    let args = CommandLine.arguments

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--content-ratio":
            index += 1
            guard index < args.count, let value = Double(args[index]), value > 0, value <= 1 else {
                throw ScriptError.usage("--content-ratio 는 0보다 크고 1 이하여야 합니다.")
            }
            config.contentRatio = value
        case "--white-threshold":
            index += 1
            guard index < args.count, let value = Int(args[index]), value >= 0, value <= 255 else {
                throw ScriptError.usage("--white-threshold 는 0~255 정수여야 합니다.")
            }
            config.whiteThreshold = UInt8(value)
        case "--verbose":
            config.verbose = true
        case "--help", "-h":
            throw ScriptError.usage(
                """
                사용법:
                  swift tools/normalize_avatar_pngs.swift [options] <png files...>

                옵션:
                  --content-ratio <0..1>   캐릭터가 캔버스 높이에서 차지할 비율 (기본 0.90)
                  --white-threshold <0..255> 거의 흰 배경을 무시할 기준값 (기본 248)
                  --verbose                처리 결과 상세 출력
                """
            )
        default:
            config.paths.append(arg)
        }
        index += 1
    }

    if config.paths.isEmpty {
        throw ScriptError.usage("정규화할 PNG 파일 경로를 하나 이상 넘겨주세요.")
    }

    return config
}

func loadImage(_ path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ScriptError.loadFailed(path)
    }
    return image
}

func foregroundBounds(for image: CGImage, whiteThreshold: UInt8) -> CGRect? {
    guard let data = image.dataProvider?.data else {
        return nil
    }
    guard let bytes = CFDataGetBytePtr(data) else {
        return nil
    }
    let width = image.width
    let height = image.height
    let bitsPerPixel = image.bitsPerPixel
    let bytesPerPixel = max(bitsPerPixel / 8, 4)
    let bytesPerRow = image.bytesPerRow

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let r = bytes[offset]
            let g = bytes[offset + 1]
            let b = bytes[offset + 2]
            let a = bytesPerPixel >= 4 ? bytes[offset + 3] : 255

            if a < 8 {
                continue
            }

            let isForeground = r < whiteThreshold || g < whiteThreshold || b < whiteThreshold
            if !isForeground {
                continue
            }

            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else {
        return nil
    }

    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1
    )
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw ScriptError.writeFailed(path)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScriptError.writeFailed(path)
    }
}

func normalizedImage(
    from image: CGImage,
    bounds: CGRect,
    contentRatio: Double
) throws -> CGImage {
    let canvasWidth = image.width
    let canvasHeight = image.height
    let targetHeight = CGFloat(contentRatio) * CGFloat(canvasHeight)
    let targetWidth = CGFloat(contentRatio) * CGFloat(canvasWidth)

    let scale = min(targetHeight / bounds.height, targetWidth / bounds.width)
    let scaledWidth = bounds.width * scale
    let scaledHeight = bounds.height * scale
    let originX = (CGFloat(canvasWidth) - scaledWidth) / 2
    let originY = (CGFloat(canvasHeight) - scaledHeight) / 2

    guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
        throw ScriptError.createContextFailed
    }

    guard let context = CGContext(
        data: nil,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ScriptError.createContextFailed
    }

    context.interpolationQuality = .high
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

    guard let cropped = image.cropping(to: bounds.integral) else {
        throw ScriptError.createContextFailed
    }

    context.draw(
        cropped,
        in: CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight)
    )

    guard let output = context.makeImage() else {
        throw ScriptError.createContextFailed
    }
    return output
}

do {
    let config = try parseArgs()
    for path in config.paths {
        let image = try loadImage(path)
        guard let bounds = foregroundBounds(for: image, whiteThreshold: config.whiteThreshold) else {
            throw ScriptError.noForeground(path)
        }
        let normalized = try normalizedImage(
            from: image,
            bounds: bounds,
            contentRatio: config.contentRatio
        )
        try writePNG(normalized, to: path)
        if config.verbose {
            let contentHeight = Int(bounds.height.rounded())
            let targetHeight = Int((CGFloat(image.height) * CGFloat(config.contentRatio)).rounded())
            print("[OK] \(path) foreground=\(contentHeight)px -> target=\(targetHeight)px")
        }
    }
} catch {
    fputs("ERROR: \(error)\n", stderr)
    exit(1)
}
