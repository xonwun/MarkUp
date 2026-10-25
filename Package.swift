// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MarkUp", platforms: [.macOS(.v14)], products: [.executable(name: "MarkUp", targets: ["MarkUp"])], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")], targets: [.executableTarget(name: "MarkUp", dependencies: [.product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/Web")])])
