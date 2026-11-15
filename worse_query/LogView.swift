import SwiftUI

struct LogView: View {
    @ObservedObject var console: Console
    /// Sileo UI: dark page + white mono text. False = the classic
    /// grouped background.
    var sileo: Bool = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(console.output)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(sileo ? .white.opacity(0.85) : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        // Room for the shell's floating pill tab bar.
                        .padding(.bottom, sileo ? 100 : 0)
                        .id("log-bottom")
                }
                .background(sileo ? Sileo.background : Color(.systemGroupedBackground))
                .navigationTitle("Log")
                .navigationBarTitleDisplayMode(sileo ? .inline : .large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            console.output = ""
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onChange(of: console.output) { _, _ in
                    withAnimation {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
}
