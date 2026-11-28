import SwiftUI

struct LogView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var console: Console

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header block (v8.0 fix): kicker + big
                        // title + subtitle, replacing the hero
                        // card. The console itself stays plain.
                        WTPageHeader(
                            kicker: "WORKTWEAKS • LOG",
                            title: wtLang.tr("Log"),
                            subtitle: wtLang.tr("Live console output — newest lines at the bottom."),
                            friend: .cat
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
                // Always inline: the page carries its own header
                // block (kicker + big title).
                .navigationBarTitleDisplayMode(.inline)
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
