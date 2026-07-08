import AppKit
import Foundation
import Testing

@Suite("App icon asset")
struct AppIconAssetTests {
    @Test
    func appIconImagesetAssignsFilenamesForAllMacSlots() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconsetURL = packageRoot
            .appendingPathComponent("PikiApp/Resources/Assets.xcassets/AppIcon.appiconset")
        let contentsURL = packageRoot
            .appendingPathComponent("PikiApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")

        let data = try Data(contentsOf: contentsURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let images = object?["images"] as? [[String: Any]] ?? []
        let filenames = images.compactMap { $0["filename"] as? String }

        #expect(images.count == 10)
        #expect(images.allSatisfy { ($0["filename"] as? String)?.isEmpty == false })
        #expect(filenames.allSatisfy { FileManager.default.fileExists(atPath: iconsetURL.appendingPathComponent($0).path) })
    }

    @Test
    func appIconUsesRoundedMaskInsteadOfFullSquareCanvas() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconURL = packageRoot
            .appendingPathComponent("PikiApp/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png")

        let data = try Data(contentsOf: iconURL)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let topLeft = try #require(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1))
        let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))

        #expect(topLeft.alphaComponent < 0.05)
        #expect(center.alphaComponent > 0.95)
    }

    @Test
    func appIconCentersAndScalesLogoWordmarkAggressively() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconURL = packageRoot
            .appendingPathComponent("PikiApp/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png")

        let data = try Data(contentsOf: iconURL)
        let bitmap = try #require(NSBitmapImageRep(data: data))

        var minX = bitmap.pixelsWide
        var maxX = 0
        var minY = bitmap.pixelsHigh
        var maxY = 0
        var foundWordmark = false

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.alphaComponent > 0.9 &&
                    color.redComponent < 0.5 &&
                    color.greenComponent < 0.5 &&
                    color.blueComponent < 0.5 {
                    foundWordmark = true
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        #expect(foundWordmark)

        let wordmarkWidth = maxX - minX + 1
        let wordmarkHeight = maxY - minY + 1
        let wordmarkCenterY = Double(minY + maxY) / 2
        let canvasCenterY = Double(bitmap.pixelsHigh) / 2

        #expect(wordmarkWidth >= 220)
        #expect(wordmarkHeight >= 120)
        #expect(abs(wordmarkCenterY - canvasCenterY) <= 8)
    }
}
