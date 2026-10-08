import Testing

@testable import HyperBufKit

@Test func mimeTypes() {
    #expect(MimeType.forExtension("svg") == "image/svg+xml")
    #expect(MimeType.forExtension("JS") == "text/javascript; charset=utf-8")
    #expect(MimeType.forExtension("wasm") == "application/wasm")
    #expect(MimeType.forExtension("unknown") == "application/octet-stream")
}

@Test func onlyImageExtensionsAreServedAsProjectResources() {
    #expect(MimeType.imageExtensions == ["png", "jpg", "jpeg", "gif", "webp", "svg"])
}
