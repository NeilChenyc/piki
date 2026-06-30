import Foundation
import Testing

@Suite("Main page logo asset")
struct MainPageLogoAssetTests {
    @Test
    func mainPageLogoImagesetPointsAtStandardMainPageFilename() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentsURL = packageRoot
            .appendingPathComponent("PikiApp/Resources/Assets.xcassets/MainPageLogo.imageset/Contents.json")

        let data = try Data(contentsOf: contentsURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let images = object?["images"] as? [[String: Any]]
        let filename = images?.first?["filename"] as? String

        #expect(filename == "mainpage-logo.png")
    }
}
