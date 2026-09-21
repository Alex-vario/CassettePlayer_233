// swift-tools-version: 5.9

import PackageDescription

let package = Package(

    name: "CassettePlayer",

    platforms: [

        .macOS(.v13)

    ],

    products: [

        .executable(

            name: "CassettePlayer",

            targets: ["CassettePlayer"]

        )

    ],

    targets: [

        .executableTarget(

            name: "CassettePlayer",

            resources: [

                .process("Resources")
            ]

        )

    ]

)