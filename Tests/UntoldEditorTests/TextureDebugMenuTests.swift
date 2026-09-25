//
//  TextureDebugMenuTests.swift
//  UntoldEditorTests
//

@testable import UntoldEditor
import UntoldEngine
import XCTest

final class TextureDebugMenuTests: XCTestCase {
    private var savedMode: RenderDebugViewMode = .lit

    override func setUp() {
        super.setUp()
        savedMode = renderDebugViewMode
    }

    override func tearDown() {
        setRendering(.debugView(savedMode))
        super.tearDown()
    }

    func testEveryEngineDebugModeHasExactlyOneMenuOption() {
        XCTAssertEqual(TextureDebugOption.allCases.count, RenderDebugViewMode.allCases.count)
        XCTAssertEqual(
            Set(TextureDebugOption.allCases.map(\.engineMode.rawValue)),
            Set(RenderDebugViewMode.allCases.map(\.rawValue))
        )
    }

    func testSelectingEachOptionUpdatesEngineAndCurrentCheckmarkValue() {
        for option in TextureDebugOption.allCases {
            TextureDebugOption.current = option
            XCTAssertEqual(renderDebugViewMode, option.engineMode)
            XCTAssertEqual(TextureDebugOption.current, option)
        }
    }

    func testMaterialTextureOptionsHaveExpectedLabelsAndGroup() {
        XCTAssertEqual(TextureDebugOption.albedo.title, "Albedo")
        XCTAssertEqual(TextureDebugOption.roughness.title, "Roughness")
        XCTAssertEqual(TextureDebugOption.metallic.title, "Metallic")
        XCTAssertEqual(TextureDebugOption.normal.title, "Normal")
        XCTAssertEqual(TextureDebugOption.roughness.group, .material)
        XCTAssertEqual(TextureDebugOption.metallic.group, .material)
    }
}
