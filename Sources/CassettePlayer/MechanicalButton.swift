import SwiftUI

struct MechanicalButton: View {

    let width: CGFloat
    let height: CGFloat

    let isPressed: Bool
    let action: () -> Void

    var body: some View {

        Button(action: action) {

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    PanelMaterials.aluminum
                )
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 2
                    )
                    .stroke(
                        Color.black.opacity(0.55),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: .black.opacity(
                        isPressed ? 0.7 : 0.45
                    ),
                    radius: isPressed ? 1 : 3,
                    y: isPressed ? 1 : 3
                )
        }
        .buttonStyle(.plain)
        .frame(
            width: width,
            height: height
        )
        .offset(
            y: isPressed ? 2 : 0
        )
    }
}