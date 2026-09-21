import SwiftUI

struct ShuffleIcon: View {

    var isActive: Bool = false

    var body: some View {

        GeometryReader { geometry in

            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {

                Path { path in

                    path.move(
                        to: CGPoint(
                            x: 1,
                            y: h * 0.28
                        )
                    )

                    path.addCurve(
                        to: CGPoint(
                            x: w - 5,
                            y: h * 0.72
                        ),
                        control1: CGPoint(
                            x: w * 0.28,
                            y: h * 0.28
                        ),
                        control2: CGPoint(
                            x: w * 0.55,
                            y: h * 0.72
                        )
                    )
                }
                .stroke(
                    isActive
                        ? Color.green.opacity(0.95)
                        : Color.white.opacity(0.72),
                    style: StrokeStyle(
                        lineWidth: 1.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                Path { path in

                    path.move(
                        to: CGPoint(
                            x: 1,
                            y: h * 0.72
                        )
                    )

                    path.addCurve(
                        to: CGPoint(
                            x: w - 5,
                            y: h * 0.28
                        ),
                        control1: CGPoint(
                            x: w * 0.28,
                            y: h * 0.72
                        ),
                        control2: CGPoint(
                            x: w * 0.55,
                            y: h * 0.28
                        )
                    )
                }
                .stroke(
                    isActive
                        ? Color.green.opacity(0.95)
                        : Color.white.opacity(0.72),
                    style: StrokeStyle(
                        lineWidth: 1.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                Path { path in

                    path.move(
                        to: CGPoint(
                            x: w - 8,
                            y: h * 0.28 - 3
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: w - 4,
                            y: h * 0.28
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: w - 8,
                            y: h * 0.28 + 3
                        )
                    )
                }
                .stroke(
                    isActive
                        ? Color.green.opacity(0.95)
                        : Color.white.opacity(0.72),
                    style: StrokeStyle(
                        lineWidth: 1.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                Path { path in

                    path.move(
                        to: CGPoint(
                            x: w - 8,
                            y: h * 0.72 - 3
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: w - 4,
                            y: h * 0.72
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: w - 8,
                            y: h * 0.72 + 3
                        )
                    )
                }
                .stroke(
                    isActive
                        ? Color.green.opacity(0.95)
                        : Color.white.opacity(0.72),
                    style: StrokeStyle(
                        lineWidth: 1.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .aspectRatio(
            1.5,
            contentMode: .fit
        )
    }
}


struct RepeatIcon: View {

    enum Mode {
        case off
        case all
        case one
    }

    var mode: Mode = .off

    var body: some View {

        GeometryReader { geometry in

            let w = geometry.size.width
            let h = geometry.size.height

            ZStack {

                Path { path in

                    path.move(
                        to: CGPoint(
                            x: 4,
                            y: h * 0.38
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: w - 5,
                            y: h * 0.38
                        )
                    )

                    path.addCurve(
                        to: CGPoint(
                            x: w - 5,
                            y: h * 0.68
                        ),
                        control1: CGPoint(
                            x: w - 1,
                            y: h * 0.38
                        ),
                        control2: CGPoint(
                            x: w - 1,
                            y: h * 0.68
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: 7,
                            y: h * 0.68
                        )
                    )
                }
                .stroke(
                    mode == .off
                        ? Color.white.opacity(0.72)
                        : Color.green.opacity(0.95),
                    style: StrokeStyle(
                        lineWidth: 1.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                Path { path in

                    path.move(
                        to: CGPoint(
                            x: 7,
                            y: h * 0.68 - 4
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: 3,
                            y: h * 0.68
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: 7,
                            y: h * 0.68 + 4
                        )
                    )
                }
                .stroke(
                    mode == .off
                        ? Color.white.opacity(0.72)
                        : Color.green.opacity(0.95),
                    style: StrokeStyle(
                        lineWidth: 1.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                Path { path in

                    path.move(
                        to: CGPoint(
                            x: w - 7,
                            y: h * 0.38 - 4
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: w - 3,
                            y: h * 0.38
                        )
                    )

                    path.addLine(
                        to: CGPoint(
                            x: w - 7,
                            y: h * 0.38 + 4
                        )
                    )
                }
                .stroke(
                    mode == .off
                        ? Color.white.opacity(0.72)
                        : Color.green.opacity(0.95),
                    style: StrokeStyle(
                        lineWidth: 1.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                if mode == .one {

                    Text("1")
                        .font(
                            .system(
                                size: 7,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.green.opacity(0.95)
                        )
                }
            }
        }
        .aspectRatio(
            1.5,
            contentMode: .fit
        )
    }
}