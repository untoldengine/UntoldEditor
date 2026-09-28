//
//  ToolOutputLogTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import UntoldEditor
import UntoldEngine
import XCTest

/// The output of an export that stopped on a texture it could not write. Logged as two
/// entries, the Console showed four lines of each: the line that names the texture is
/// the ninth of the error stream.
final class ToolOutputLogTests: XCTestCase {
    private let failedExportStdout = """
    Using Blender: /Applications/Blender.app/Contents/MacOS/Blender
    Opening building.blend ...
      Processing 2 mesh(es) ...
      [1/2 |  50.00%] Floor_mat0
    [progress] asset export:   0.00% (0/5) Extract meshes - 1/2 Floor_mat0
      [2/2 | 100.00%] Floor_mat1
    [progress] asset export:   0.00% (0/5) Extract meshes - 2/2 Floor_mat1
      Warning: mesh 'Floor_mat1' has no UV map; export-time baking will require one
    [progress] asset export:  40.00% (2/5) Stage nodes - 1/2 Floor_mat0

    """

    private let failedExportStderr = """
    libpng error: ICC profile too short
    libpng error: No IDATs written into file
    Traceback (most recent call last):
      File "/scripts/untoldexporter.py", line 20, in <module>
        raise SystemExit(main(__import__("sys").argv))
      File "/scripts/untoldexplorer.py", line 3082, in write_blender_image_to_path
        image.save()
    RuntimeError: Error: Could not write image: internal error, see console
    Error: Image 'garage_floor_nor_gl_4k.jpg.001' could not be saved to '/Models/Cube_008/Textures/garage_floor_nor_gl_4k.png'


    Error: script failed, file: '/scripts/untoldexporter.py', exiting.

    """

    func testEveryLineOfAFailedExportGetsItsOwnEntry() {
        let lines = toolOutputLines(stdout: failedExportStdout, stderr: failedExportStderr, failed: true)

        XCTAssertEqual(lines.filter { $0.level == .info }.map(\.text), [
            "Using Blender: /Applications/Blender.app/Contents/MacOS/Blender",
            "Opening building.blend ...",
            "  Processing 2 mesh(es) ...",
        ])
        XCTAssertEqual(lines.filter { $0.level == .warning }.map(\.text), [
            "  Warning: mesh 'Floor_mat1' has no UV map; export-time baking will require one",
        ])

        let errors = lines.filter { $0.level == .error }.map(\.text)
        XCTAssertEqual(errors.count, 10)
        XCTAssertEqual(errors.first, "libpng error: ICC profile too short")
        XCTAssertEqual(
            errors[8],
            "Error: Image 'garage_floor_nor_gl_4k.jpg.001' could not be saved to '/Models/Cube_008/Textures/garage_floor_nor_gl_4k.png'"
        )
        XCTAssertEqual(errors.last, "Error: script failed, file: '/scripts/untoldexporter.py', exiting.")
        XCTAssertEqual(lines.last?.level, .error, "the error comes last, where the Console scrolls to")
    }

    func testProgressLinesAreLeftOut() {
        let lines = toolOutputLines(stdout: failedExportStdout, stderr: "", failed: false)

        XCTAssertFalse(lines.contains { $0.text.contains("[progress]") })
        XCTAssertFalse(lines.contains { $0.text.contains("[1/2 |") })
        XCTAssertEqual(lines.count, 4)
    }

    func testWarningIsFollowedByTheListOfWhatItIsAbout() {
        let stdout = """
        Wrote building.untoldpack (2 model(s))
        Warning: 2 texture(s) could not be exported. The materials that use them were written without them:
          - 'floor_normal.jpg' could not be written. It was the normal texture of material 'floor' on object 'Floor'.
          - 'wall_normal.jpg' could not be written. It was the normal texture of material 'wall' on object 'Wall'.
        Blender 5.2.0 LTS
        """

        let lines = toolOutputLines(stdout: stdout, stderr: "", failed: false)

        XCTAssertEqual(lines.map(\.level), [.info, .warning, .warning, .warning, .info])
        XCTAssertEqual(taskDetail("Wrote building.untoldpack", warningsIn: lines), "Wrote building.untoldpack (3 warnings, see Console)")
    }

    func testErrorStreamOfAToolThatCarriedOnIsAWarning() {
        let lines = toolOutputLines(stdout: "", stderr: "libpng error: ICC profile too short\n", failed: false)

        XCTAssertEqual(lines, [ToolOutputLine(level: .warning, text: "libpng error: ICC profile too short")])
    }

    func testToolThatPrintedNothingLogsNothing() {
        XCTAssertEqual(toolOutputLines(stdout: "", stderr: "\n  \n", failed: true), [])
    }

    func testTaskDetailPointsAtTheConsoleOnlyWhenThereAreWarnings() {
        let warning = ToolOutputLine(level: .warning, text: "Warning: something")
        let info = ToolOutputLine(level: .info, text: "Wrote building.untold")

        XCTAssertEqual(taskDetail("Wrote building.untold", warningsIn: [info]), "Wrote building.untold")
        XCTAssertEqual(taskDetail("Wrote building.untold", warningsIn: [info, warning]), "Wrote building.untold (1 warning, see Console)")
        XCTAssertEqual(
            taskDetail("Wrote building.untold", warningsIn: [warning, info, warning]),
            "Wrote building.untold (2 warnings, see Console)"
        )
    }
}
