// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PerchCertificates", platforms: [.macOS(.v14)], products: [
    .library(name: "PerchCertificates", type: .static, targets: ["PerchCertificates"])
], dependencies: [
    .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.16.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.0.0"),
    .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.4.0")
], targets: [.target(name: "PerchCertificates", dependencies: [
    .product(name: "X509", package: "swift-certificates"),
    .product(name: "Crypto", package: "swift-crypto"),
    .product(name: "SwiftASN1", package: "swift-asn1")
])])
