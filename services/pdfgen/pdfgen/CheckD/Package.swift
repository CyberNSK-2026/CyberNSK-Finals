// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CheckD",
    platforms: [
        .macOS(.v15),
        .custom("linux", versionString: "22.04")
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "CheckD",
            targets: ["CheckD"]
        ),
        .executable(
            name: "CheckDPrintService",
            targets: ["CheckDPrintService"]
        ),
        .library(name: "FastCGI2", targets: ["FastCGI2"]),
   ],
   dependencies: [
       .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
       .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
       .package(url: "https://github.com/apple/swift-nio.git", from: "2.76.1")
   ],

    targets: [
        .target(
            name: "ServiceStdio",
            dependencies: []
        ),
        .executableTarget(
            name: "CheckD",
            dependencies: [
                "FastCGI2",
                "ServiceStdio",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]
        ),
        .executableTarget(
            name: "CheckDPrintService",
            dependencies: [
                "FastCGI2",
                "ServiceStdio",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
        .target(
            name: "FastCGI2",
            dependencies: [
                "ServiceStdio",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")
            ]
        )

    ]
)
