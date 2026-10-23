// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MarkUp", platforms: [.macOS(.v14)], products: [.executable(name: "MarkUp", targets: ["MarkUp"])], targets: [.executableTarget(name: "MarkUp", resources: [.copy("Resources/Web")])])
