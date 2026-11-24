import SwiftUI

// MARK: - Lock Screen Footnote editor
//
// One editor, reached from the Tweaks tab's Add feature
// section. All
// work goes through FootnoteManager (directory grant,
// read-modify-write in place, verify by re-reading). When the
// directory grant or the read fails, the page shows an honest
// blocked state and nothing can be written from here.
//
// Since v3.8 the page renders as Liquid Glass cards
// (WTGlassPage/WTSectionCard), like every other page —
// presentation only; the editor behaves exactly as before.

struct FootnoteView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var manager = FootnoteManager()
    @State private var text = ""
    @State private var showRestartChoice = false
    @State private var showManualRestartGuide = false
    @State private var writeFailed = false

    var body: some View {
        WTGlassPage {
            if case .blocked(let reason) = manager.state {
                WTSectionCard(footer: wtLang.tr("Nothing was written.")) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(wtLang.tr("Lock Screen Footnote is unavailable"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            } else if case .ready = manager.state {
                WTSectionCard(header: wtLang.tr("Footnote"), footer: wtLang.tr("%d character(s). The text appears in small type at the bottom of the Lock Screen. Leave it empty and tap Apply Footnote to remove the footnote.", text.count)) {
                    TextField(wtLang.tr("Footnote text"), text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                }

                WTSectionCard(footer: wtLang.tr("Writes SharedDeviceConfiguration.plist in place, keeping every other key in the file. SpringBoard reads the file when it starts, so a respring or restart is needed to see the change.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            if manager.apply(text: text) {
                                showRestartChoice = true
                            } else {
                                writeFailed = true
                            }
                        } label: {
                            Text(wtLang.tr("Apply Footnote"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                        .disabled(manager.isWriting)

                        if manager.hasFootnote {
                            Divider()
                                .padding(.leading, 14)

                            Button(role: .destructive) {
                                if manager.removeFootnote() {
                                    text = ""
                                    showRestartChoice = true
                                } else {
                                    writeFailed = true
                                }
                            } label: {
                                Text(wtLang.tr("Remove Footnote"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                            }
                            .disabled(manager.isWriting)
                        }
                    }
                }
            } else {
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(wtLang.tr("Opening the configuration profiles…"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(wtLang.tr("Lock Screen Footnote"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.load()
            text = manager.footnote
        }
        .confirmationDialog(wtLang.tr("Footnote Updated"), isPresented: $showRestartChoice, titleVisibility: .visible) {
            Button(wtLang.tr("Respring")) { RespringCenter.shared.trigger() }
            Button(wtLang.tr("Restart Device")) {
                showManualRestartGuide = true
            }
            Button(wtLang.tr("Later"), role: .cancel) { }
        } message: {
            Text(wtLang.tr("SpringBoard reads the footnote when it starts — respring or restart to see it on the Lock Screen."))
        }
        .alert(ManualRestartGuide.title, isPresented: $showManualRestartGuide) {
            Button(wtLang.tr("OK")) { }
        } message: {
            Text(ManualRestartGuide.message)
        }
        .alert(wtLang.tr("Couldn't Save"), isPresented: $writeFailed) {
            Button(wtLang.tr("OK")) { }
        } message: {
            Text(wtLang.tr("Writing the footnote failed — the details are in the Log."))
        }
    }
}
