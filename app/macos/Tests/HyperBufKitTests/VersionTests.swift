import Testing

@testable import HyperBufKit

@Test func versionLooksLikeSemver() {
    let parts = hyperBufVersion.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
