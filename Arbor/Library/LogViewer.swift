import SwiftUI

struct LogViewer: View {
    let title: String
    let logText: String?
    let showClose: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let displayText = logText?.isEmpty == false ? (logText ?? "") : "No logs captured."

        ScrollViewReader { proxy in
            ScrollView {
                Text(displayText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Color("PrimaryText"))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .background(BackgroundColor.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}
