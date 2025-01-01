// swift-tools-version:6.0

import PackageDescription

let package = Package(
  name: "Packages",
  platforms: [.iOS(.v16), .macOS(.v14)],
  products: [
    .library(name: "KernelBridge", targets: ["KernelBridge"]),
    .library(name: "Kernel", targets: ["Kernel"]),
    .library(name: "Parameters", targets: ["Parameters"]),
    .library(name: "ParameterAddress", targets: ["ParameterAddress"])
  ],
  dependencies: [
    .package(url: "https://github.com/bradhowes/AUv3Support", exact: "16.1.1")
    // .package(name: "AUv3SupportPackage", path: "/Users/howes/src/Mine/AUv3Support")
  ],
  targets: [
    .target(
      name: "KernelBridge",
      dependencies: [
        "Kernel",
        .product(name: "AUv3-Support", package: "AUv3Support", condition: .none),
      ],
      exclude: ["README.md"]
    ),
    .target(
      name: "Kernel",
      dependencies: [
        .product(name: "AUv3-Support", package: "AUv3Support", condition: .none),
        .product(name: "AUv3-DSP-Headers", package: "AUv3Support", condition: .none),
        "ParameterAddress"
      ],
      exclude: ["README.md"],
      cxxSettings: [.unsafeFlags(["-fmodules", "-fcxx-modules"], .none)]
    ),
    .target(
      name: "ParameterAddress",
      dependencies: [
        .product(name: "AUv3-Support", package: "AUv3Support", condition: .none),
      ],
      exclude: ["README.md"]
    ),
    .target(
      name: "Parameters",
      dependencies: [
        .product(name: "AUv3-Support", package: "AUv3Support", condition: .none),
        "Kernel"
      ],
      exclude: ["README.md"]
    ),
    .testTarget(
      name: "KernelTests",
      dependencies: ["Kernel", "ParameterAddress"],
      cxxSettings: [.unsafeFlags(["-fmodules", "-fcxx-modules"], .none)],
      linkerSettings: [.linkedFramework("AVFoundation")]
    ),
    .testTarget(
      name: "ParameterAddressTests",
      dependencies: ["ParameterAddress"]
    ),
    .testTarget(
      name: "ParametersTests",
      dependencies: ["Parameters"]
    ),
  ],
  cxxLanguageStandard: .cxx20
)
