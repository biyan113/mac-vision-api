// 对一张截图做 OCR，打印识别到的文字，并检查指定的文字是否都出现在界面上。
// 用法：swift read-screenshot.swift <图片> [必须出现的文字 ...]
import AppKit
import Foundation
import Vision

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("用法：read-screenshot.swift <图片> [必须出现的文字 ...]\n".utf8))
    exit(2)
}

guard let image = NSImage(contentsOfFile: arguments[1]),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("无法读取图片 \(arguments[1])\n".utf8))
    exit(2)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
print("截图尺寸：\(cgImage.width)x\(cgImage.height)")
print("识别到 \(lines.count) 行文字：")
for line in lines {
    print("  | \(line)")
}

// 去掉空白后再比较，避免 OCR 在字符间插入空格导致误判
let haystack = lines.joined(separator: "\n").replacingOccurrences(of: " ", with: "")
let missing = arguments.dropFirst(2).filter { !haystack.contains($0.replacingOccurrences(of: " ", with: "")) }
if !missing.isEmpty {
    print("界面上没有找到：\(missing.joined(separator: "、"))")
    exit(1)
}
print("界面检查通过")
