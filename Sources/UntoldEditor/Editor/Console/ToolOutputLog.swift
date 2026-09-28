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
/// What the tool wrote to its error stream is an error when the tool failed, and a warning
/// when it carried on regardless.
func toolOutputLines(stdout: String, stderr: String, failed: Bool) -> [ToolOutputLine] {
    var lines: [ToolOutputLine] = []

    var isListingWarnings = false
    for text in printedLines(of: stdout) {
        let content = text.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("Warning:") {
            isListingWarnings = true
        } else if !content.hasPrefix("- ") {
            // A warning may be followed by the list of what it is about.
            isListingWarnings = false
        }
        lines.append(ToolOutputLine(level: isListingWarnings ? .warning : .info, text: text))
    }

    for text in printedLines(of: stderr) {
        lines.append(ToolOutputLine(level: failed ? .error : .warning, text: text))
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

/// What a finished task says, with a pointer to the Console when its tool had warnings.
func taskDetail(_ detail: String, warningsIn lines: [ToolOutputLine]) -> String {
    let warningCount = lines.count(where: { $0.level == .warning })
    switch warningCount {
    case 0: return detail
    case 1: return "\(detail) (1 warning, see Console)"
    default: return "\(detail) (\(warningCount) warnings, see Console)"
    }
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
