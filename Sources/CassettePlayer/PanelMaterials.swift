import SwiftUI

enum PanelMaterials {

    // Основная окрашенная металлическая панель
    static let mainPanel =
        LinearGradient(
            stops: [
                .init(color: Color(white: 0.105), location: 0.00),
                .init(color: Color(white: 0.085), location: 0.18),
                .init(color: Color(white: 0.095), location: 0.50),
                .init(color: Color(white: 0.075), location: 0.82),
                .init(color: Color(white: 0.095), location: 1.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

    // Тёмный фактурный пластик
    static let texturedPlastic =
        Color(
            red: 0.038,
            green: 0.040,
            blue: 0.042
        )

    // Пластик кассеты
    static let cassettePlastic =
        Color(
            red: 0.11,
            green: 0.115,
            blue: 0.12
        )

    // Необработанный алюминий
    static let aluminum =
        LinearGradient(
            stops: [
                .init(color: Color(white: 0.78), location: 0.00),
                .init(color: Color(white: 0.52), location: 0.22),
                .init(color: Color(white: 0.86), location: 0.48),
                .init(color: Color(white: 0.58), location: 0.72),
                .init(color: Color(white: 0.76), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

    // Маркировка, нанесённая на панель
    static let marking =
        Color(white: 0.86)
}