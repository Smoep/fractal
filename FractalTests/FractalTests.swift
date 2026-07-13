//
//  FractalTests.swift
//  FractalTests
//
//  Created by Jos on 10/4/26.
//

import Foundation
import Testing
@testable import Fractal

struct FractalTests {

    @Test func radialMenuBackupRoundTrip() throws {
        let categories = RadialMenuStore.defaultCategories
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let data = try RadialMenuBackupCodec.encode(categories: categories, exportedAt: exportedAt)
        let imported = try RadialMenuBackupCodec.decode(data)

        #expect(imported.count == categories.count)
        #expect(imported.first?.id == categories.first?.id)
        #expect(imported.first?.actions.first?.id == categories.first?.actions.first?.id)
    }

    @Test func radialMenuBackupRejectsOtherFiles() {
        let data = Data("{\"version\":1,\"categories\":[]}".utf8)

        #expect(throws: RadialMenuBackupError.self) {
            try RadialMenuBackupCodec.decode(data)
        }
    }

    @Test func radialMenuBackupRejectsEmptyMenus() throws {
        let data = try RadialMenuBackupCodec.encode(categories: [])

        #expect(throws: RadialMenuBackupError.self) {
            try RadialMenuBackupCodec.decode(data)
        }
    }

    @Test func radialTreeBackupStillImportsAfterRename() throws {
        let current = try RadialMenuBackupCodec.encode(categories: RadialMenuStore.defaultCategories)
        var object = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object["format"] = RadialMenuBackup.legacyFormatIdentifier
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let imported = try RadialMenuBackupCodec.decode(legacy)
        #expect(imported.count == RadialMenuStore.defaultCategories.count)
    }

}
