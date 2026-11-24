import SwiftUI

// MARK: - Wi-Fi File Sharing page
//
// Start/stop the local HTTP file server (WiFiShareServer):
// the phone's address and the per-session PIN are shown here
// — a browser on the same Wi-Fi opens the address, signs in
// as "worktweaks" with the PIN, and can fetch zip saves,
// drop .tendies files and deploy packages, or browse this
// app's Documents folder.
//
// The server stops by itself when this page is left or the
// app goes to the background — iOS suspends background
// sockets anyway, so a server left running would only fail
// silently. Keep this page open while transferring.

struct WiFiShareView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var server = WiFiShareServer()
    @State private var backgroundObserver: NSObjectProtocol?

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("Server"), footer: wtLang.tr("The server shares this app's Documents folder only — SaveVaultBackups, staged vaults and uploads. Nothing outside it is ever served. Keep this page open while transferring: the server stops when you leave the page or the app goes to the background.")) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        RowIcon(systemImage: server.isRunning ? "wifi" : "wifi.slash")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.isRunning ? wtLang.tr("Running") : wtLang.tr("Stopped"))
                                .font(.subheadline.weight(.semibold))
                            Text(server.isRunning ? server.addressText : wtLang.tr("Start the server to get its address."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.leading, 14)

                    Button {
                        if server.isRunning {
                            server.stop()
                        } else {
                            server.start()
                        }
                        SoundEffects.playTap()
                    } label: {
                        Text(server.isRunning ? wtLang.tr("Stop Server") : wtLang.tr("Start Server"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }

            if server.isRunning {
                WTSectionCard(header: wtLang.tr("Sign In"), footer: wtLang.tr("The browser asks for these credentials once, then remembers them for the session.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        LabeledContent(wtLang.tr("Address"), value: server.addressText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        Divider()
                            .padding(.leading, 14)
                        LabeledContent(wtLang.tr("Username"), value: WiFiShareServer.username)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        Divider()
                            .padding(.leading, 14)
                        LabeledContent(wtLang.tr("PIN"), value: server.pin)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                }

                if !server.statusMessage.isEmpty {
                    WTSectionCard {
                        Text(server.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                if !server.requestLog.isEmpty {
                    WTSectionCard(header: wtLang.tr("Recent Requests")) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(server.requestLog, id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .navigationTitle(wtLang.tr("Wi-Fi File Sharing"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                // iOS suspends background sockets — stop
                // cleanly instead of failing silently.
                server.stop()
            }
        }
        .onDisappear {
            server.stop()
            if let observer = backgroundObserver {
                NotificationCenter.default.removeObserver(observer)
                backgroundObserver = nil
            }
        }
    }
}
