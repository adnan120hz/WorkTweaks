import SwiftUI

// MARK: - Lock Screen Footnote editor
//
// One editor, reached from the Tweaks tab's Add feature
// section. All
// work goes through FootnoteManager (directory grant,
// read-modify-write in place, verify by re-reading). When the
// directory grant or the read fails, the page shows an honest
// blocked state and nothing can be written from here.

struct FootnoteView: View {
    @StateObject private var manager = FootnoteManager()
    @State private var text = ""
    @State private var showRestartChoice = false
    @State private var showManualRestartGuide = false
    @State private var writeFailed = false

    var body: some View {
        Form {
            if case .blocked(let reason) = manager.state {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Lock Screen Footnote is unavailable", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Nothing was written.")
                }
            } else if case .ready = manager.state {
                Section {
                    TextField("Footnote text", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .disableAutocorrection(true)
                } header: {
                    Text("Footnote")
                } footer: {
                    Text("\(text.count) character(s). The text appears in small type at the bottom of the Lock Screen. Leave it empty and tap Apply Footnote to remove the footnote.")
                }

                Section {
                    Button("Apply Footnote") {
                        if manager.apply(text: text) {
                            showRestartChoice = true
                        } else {
                            writeFailed = true
                        }
                    }
                    .disabled(manager.isWriting)

                    if manager.hasFootnote {
                        Button("Remove Footnote", role: .destructive) {
                            if manager.removeFootnote() {
                                text = ""
                                showRestartChoice = true
                            } else {
                                writeFailed = true
                            }
                        }
                        .disabled(manager.isWriting)
                    }
                } footer: {
                    Text("Writes SharedDeviceConfiguration.plist in place, keeping every other key in the file. SpringBoard reads the file when it starts, so a respring or restart is needed to see the change.")
                }
            } else {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Opening the configuration profiles…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Lock Screen Footnote")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.load()
            text = manager.footnote
        }
        .confirmationDialog("Footnote Updated", isPresented: $showRestartChoice, titleVisibility: .visible) {
            Button("Respring") { RespringCenter.shared.trigger() }
            Button("Restart Device") {
                showManualRestartGuide = true
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("SpringBoard reads the footnote when it starts — respring or restart to see it on the Lock Screen.")
        }
        .alert(ManualRestartGuide.title, isPresented: $showManualRestartGuide) {
            Button("OK") { }
        } message: {
            Text(ManualRestartGuide.message)
        }
        .alert("Couldn't Save", isPresented: $writeFailed) {
            Button("OK") { }
        } message: {
            Text("Writing the footnote failed — the details are in the Log.")
        }
    }
}
