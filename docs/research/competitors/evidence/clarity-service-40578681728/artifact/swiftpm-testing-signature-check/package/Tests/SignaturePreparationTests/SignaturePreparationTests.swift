import Foundation
import Testing
@Test func signaturePreparationRunsStandardSwiftTesting() throws {
    let url = try #require(Bundle.module.url(forResource: "signed-resource", withExtension: "txt"))
    let actual = try Data(contentsOf: url)
    #expect(actual == Data([82, 74, 84, 32, 115, 105, 103, 110, 101, 100, 45, 114, 101, 115, 111, 117, 114, 99, 101, 10, 108, 105, 116, 101, 114, 97, 108, 32, 101, 204, 129, 32, 229, 143, 176, 229, 140, 151, 32, 240, 159, 145, 169, 240, 159, 143, 189, 226, 128, 141, 240, 159, 146, 187, 10]))
}
