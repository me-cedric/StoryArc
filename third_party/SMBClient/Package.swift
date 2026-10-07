// swift-tools-version: 5.9

import PackageDescription

// SMBClient 0.3.1, vendored, with SMB 3 dialects and SMB 3 transport encryption added.
//
// Upstream offers SMB 2.0.2 and 2.1 only, and no upstream release negotiates SMB 3.
// VENDORING.md lists every change against the upstream tag. ADR-0019 records why.
let package = Package(
  name: "SMBClient",
  platforms: [
    .macOS(.v10_15),
    .iOS(.v13),
    .visionOS(.v1)
  ],
  products: [
    .library(
      name: "SMBClient",
      targets: ["SMBClient"]
    ),
  ],
  targets: [
    .target(
      name: "SMBClient"
    ),
  ]
)
