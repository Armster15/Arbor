import SwiftUI

/// Shared form styling modifiers to match the metadata edit sheet in `PlayerScreen`.

private struct FormFieldLabelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fontWeight(.semibold)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color("PrimaryText"))
    }
}

private struct FormFieldInputModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(colorScheme == .light ? Color("Elevated") : Color.clear)
            .glassEffect()
            .cornerRadius(24)
            .foregroundStyle(Color("PrimaryText"))
            .tint(Color("PrimaryText"))
    }
}

private struct FormFieldContainerModifier: ViewModifier {
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
    }
}

private struct PrimaryActionButtonModifier: ViewModifier {
    let isLoading: Bool
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .fontWeight(.semibold)
            .buttonStyle(.glassProminent)
            .tint(Color("PrimaryBg"))
            .foregroundStyle(isLoading ? Color("PrimaryText") : Color("SecondaryText"))
            .disabled(isDisabled || isLoading)
            .padding(.horizontal)
            .padding(.bottom)
    }
}

extension View {
    func formFieldLabelStyle() -> some View {
        modifier(FormFieldLabelModifier())
    }

    func formFieldInputStyle() -> some View {
        modifier(FormFieldInputModifier())
    }

    func formFieldContainer(horizontalPadding: CGFloat = 16) -> some View {
        modifier(FormFieldContainerModifier(horizontalPadding: horizontalPadding))
    }

    func primaryActionButtonStyle(isLoading: Bool = false, isDisabled: Bool = false) -> some View {
        modifier(PrimaryActionButtonModifier(isLoading: isLoading, isDisabled: isDisabled))
    }
}
