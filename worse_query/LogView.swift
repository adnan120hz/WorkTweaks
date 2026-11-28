import SwiftUI

struct LogView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var console: Console

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Featured hero (v8.0 revamp) — the Log
                        // tab opens like the other tabs now.
                        // The console itself stays plain.
                        WTPageHero(
                            systemImage: "terminal",
                            title: wtLang.tr("Log"),
                            subtitle: wtLang.tr("Live console output — newest lines at the bottom.")
                        )

                        Text(console.output)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .wtGlassCard(cornerRadius: 16)
                            .id("log-bottom")

                        // Clearance so the last log lines are never
                        // hidden behind the floating tab bar.
                        Color.clear.frame(height: 32)
                    }
                    .padding(16)
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
