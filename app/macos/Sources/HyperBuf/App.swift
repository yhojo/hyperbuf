import HyperBufKit
import SwiftUI

@main
struct HyperBufApp: App {
    var body: some Scene {
        Window("HyperBuf", id: "main") {
            Text("HyperBuf \(hyperBufVersion)")
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
