import SwiftUI
import UIKit

#if DEBUG
struct DeveloperPythonReplScreen: View {
    @AppStorage("dev_python_repl_code") private var code = "1 + 1"
    @State private var output = ""
    @State private var isRunning = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Development-only Python REPL.")
                    .font(.subheadline)
                    .foregroundColor(Color("PrimaryText").opacity(0.8))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Code")
                        .font(.headline)
                        .foregroundColor(Color("PrimaryText"))

                    CodeEditor(text: $code)
                        .frame(minHeight: 180)
                        .padding(8)
                        .background(Color("SecondaryBg"))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 12) {
                    Button {
                        runCode()
                    } label: {
                        HStack(spacing: 8) {
                            if isRunning {
                                ProgressView()
                            }
                            Text(isRunning ? "Running..." : "Run")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color("SecondaryText"))
                    .disabled(isRunning)

                    Button("Clear Output") {
                        output = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Output") {
                        UIPasteboard.general.string = output
                    }
                    .buttonStyle(.bordered)
                    .disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output")
                        .font(.headline)
                        .foregroundColor(Color("PrimaryText"))

                    OutputViewer(text: output.isEmpty ? "No output yet." : output)
                        .frame(minHeight: 140, maxHeight: 240)
                        .padding(8)
                        .background(Color("SecondaryBg"))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(16)
        }
    }

    private func runCode() {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isRunning = true
        let wrappedCode = buildReplCode(for: code)
        pythonExecAndGetStringAsync(wrappedCode, "__repl_result__") { result in
            isRunning = false
            let value = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            output = value.isEmpty ? "No output." : result ?? ""
        }
    }

    private func buildReplCode(for source: String) -> String {
        let escaped = escapeForPythonString(source)
        return """
import io
import contextlib
import traceback
__repl_result__ = ""
__repl_output__ = None
__repl_buffer__ = io.StringIO()
_code = "\(escaped)"
try:
    with contextlib.redirect_stdout(__repl_buffer__), contextlib.redirect_stderr(__repl_buffer__):
        try:
            __repl_output__ = repr(eval(_code, globals()))
        except SyntaxError:
            exec(_code, globals())
    __repl_result__ = __repl_buffer__.getvalue()
    if not __repl_result__:
        if __repl_output__ is not None:
            __repl_result__ = __repl_output__
        else:
            __repl_result__ = "OK"
except Exception:
    __repl_result__ = traceback.format_exc()
"""
    }

    private func escapeForPythonString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
#endif

#if DEBUG
private struct CodeEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFont.monospacedSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
        view.textColor = UIColor(named: "PrimaryText")
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
#endif

#if DEBUG
private struct OutputViewer: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = UIFont.monospacedSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
        view.textColor = UIColor(named: "PrimaryText")
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
}
#endif
