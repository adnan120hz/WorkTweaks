import SwiftUI

struct LogView: View {
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
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .padding(12)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            console.output = ""
                        }
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
