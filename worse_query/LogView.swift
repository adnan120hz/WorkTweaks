import SwiftUI

struct LogView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var console: Console

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(console.output)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("log-bottom")
                    // Clearance so the last log lines are never
                    // hidden behind the floating tab bar.
                    Color.clear.frame(height: 32)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(wtLang.tr("Log"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(wtLang.tr("Clear")) {
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
