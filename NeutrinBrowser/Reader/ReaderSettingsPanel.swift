import SwiftUI

/// Font size, font and theme for reader mode.
struct ReaderSettingsPanel: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                Button {
                    settings.fontSize = max(ReaderSettings.fontSizeRange.lowerBound, settings.fontSize - 1)
                } label: {
                    Text("A").font(.system(size: 15)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Texto más pequeño")
                Divider().frame(height: 24)
                Button {
                    settings.fontSize = min(ReaderSettings.fontSizeRange.upperBound, settings.fontSize + 1)
                } label: {
                    Text("A").font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityLabel("Texto más grande")
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Picker("Fuente", selection: $settings.font) {
                ForEach(ReaderFont.allCases) { font in
                    Text(font.name).tag(font)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                ForEach(ReaderTheme.allCases) { theme in
                    Button { settings.theme = theme } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(swatch(for: theme))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                .overlay(
                                    Circle().strokeBorder(Color.neutrinBlue, lineWidth: settings.theme == theme ? 3 : 0)
                                )
                                .frame(width: 40, height: 40)
                            Text(theme.name).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
                }
            }
        }
        .padding(18)
        .frame(width: 290)
    }

    private func swatch(for theme: ReaderTheme) -> AnyShapeStyle {
        switch theme {
        case .auto:
            AnyShapeStyle(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.97), Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.07, green: 0.07, blue: 0.09)],
                                         startPoint: .leading, endPoint: .trailing))
        case .light: AnyShapeStyle(Color(red: 0.97, green: 0.97, blue: 0.99))
        case .sepia: AnyShapeStyle(Color(red: 0.96, green: 0.94, blue: 0.89))
        case .dark: AnyShapeStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
        }
    }
}
