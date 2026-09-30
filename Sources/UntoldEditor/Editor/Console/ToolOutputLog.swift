//
//  ToolOutputLog.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UntoldEngine

/// One line of what a command line tool printed, and the level the Console shows it at.
struct ToolOutputLine: Equatable {
    let level: LogLevel
    let text: String
}

/// Splits what a command line tool printed into the lines that are worth a Console entry.
///
/// The Console shows the first four lines of an entry. A tool's whole output logged as one
/// entry therefore hides everything after them: its warnings, and the error that stopped it.
/// Progress lines are left out, since an export prints thousands of them.
///
/// A line is a warning or an error when the tool marked it as one (see `markedLevel`).
/// What the tool wrote to its error stream is an error when the tool failed, and a warning
/// when it carried on regardless.
func toolOutputLines(stdout: String, stderr: String, failed: Bool) -> [ToolOutputLine] {
    var lines: [ToolOutputLine] = []

    var listLevel: LogLevel?
    for text in printedLines(of: stdout) {
        let content = text.trimmingCharacters(in: .whitespaces)
        if let level = markedLevel(of: content) {
            listLevel = level
        } else if !content.hasPrefix("- ") {
            // A warning may be followed by the list of what it is about.
            listLevel = nil
        }
        lines.append(ToolOutputLine(level: listLevel ?? .info, text: text))
    }

    for text in printedLines(of: stderr) {
        lines.append(ToolOutputLine(level: failed ? .error : .warning, text: text))
    }
    return lines
}

/// The Console lines of an export's texture compression: what the bake and the reference
/// patch printed and, when either of them failed, a warning that says what that leaves.
///
/// A compression that fails does not fail the export, so that warning is how its task
/// comes to point at the Console.
func textureCompressionLines(
    bake: (status: Int32, stdout: String, stderr: String),
    patch: (status: Int32, stdout: String, stderr: String),
    failureWarning: String
) -> [ToolOutputLine] {
    var lines = toolOutputLines(stdout: bake.stdout, stderr: bake.stderr, failed: bake.status != 0)
    lines += toolOutputLines(stdout: patch.stdout, stderr: patch.stderr, failed: patch.status != 0)
    if bake.status != 0 || patch.status != 0 {
        lines.append(ToolOutputLine(level: .warning, text: failureWarning))
    }
    return lines
}

/// Logs what a command line tool printed, one Console entry per line.
func logToolOutput(_ lines: [ToolOutputLine]) {
    for line in lines {
        switch line.level {
        case .error: Logger.logError(message: line.text)
        case .warning: Logger.logWarning(message: line.text)
        default: Logger.log(message: line.text)
        }
    }
}

/// What a finished task says, with a pointer to the Console when its tools had warnings.
/// `lines` is the output of every tool the task ran, not only the first.
func taskDetail(_ detail: String, warningsIn lines: [ToolOutputLine]) -> String {
    let warningCount = lines.count(where: { $0.level == .warning })
    switch warningCount {
    case 0: return detail
    case 1: return "\(detail) (1 warning, see Console)"
    default: return "\(detail) (\(warningCount) warnings, see Console)"
    }
}

/// How the tools mark a line: the exporters with "Warning:" or "Error:", texbake.py with
/// "[warn]" or "[error]".
private func markedLevel(of content: String) -> LogLevel? {
    let lowercased = content.lowercased()
    if lowercased.hasPrefix("warning:") || lowercased.hasPrefix("[warn]") {
        return .warning
    }
    if lowercased.hasPrefix("error:") || lowercased.hasPrefix("[error]") {
        return .error
    }
    return nil
}

private func printedLines(of output: String) -> [String] {
    output
        .components(separatedBy: .newlines)
        .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        .filter { !$0.isEmpty && !isProgressLine($0) }
}

/// "[progress] asset export: 40.00% (2/5) Write chunks" and "  [675/698 |  96.70%] Floor".
private func isProgressLine(_ line: String) -> Bool {
    line.range(of: "^\\s*\\[(progress\\]|\\d+/\\d+ \\|)", options: .regularExpression) != nil
}
