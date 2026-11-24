import SwiftUI

// MARK: - Configuration Profiles page (read-only)
//
// Supervision audit, Lock Screen footnote / asset tag, the
// parsed installed profiles, and the raw file list of the
// ConfigurationProfiles directory. Nothing on this page
// writes, installs or removes anything — supervision in
// particular is permanently read-only (see ProfileViewer.swift).

struct ProfileViewerView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @StateObject private var viewer = ProfileViewer()

    var body: some View {
        WTGlassPage {
            switch viewer.state {
            case .idle, .loading:
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(wtLang.tr("Reading the configuration profiles…"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            case .blocked(let message):
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(wtLang.tr("Couldn't read the configuration profiles."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            case .ready:
                if let audit = viewer.audit {
                    WTSectionCard(header: wtLang.tr("Supervision")) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: supervisionIcon(audit.state))
                                    .foregroundStyle(supervisionColor(audit.state))
                                Text(supervisionTitle(audit.state))
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(audit.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let org = audit.organizationName {
                                Text(wtLang.tr("Organization: %@", org))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    WTSectionCard(header: wtLang.tr("Device Configuration")) {
                        VStack(alignment: .leading, spacing: 0) {
                            LabeledContent(wtLang.tr("Lock Screen Footnote"), value: audit.footnote ?? wtLang.tr("Not set"))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            Divider()
                                .padding(.leading, 14)
                            LabeledContent(wtLang.tr("Asset Tag"), value: audit.assetTag ?? wtLang.tr("Not set"))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                        }
                    }
                }

                WTSectionCard(
                    header: wtLang.tr("Installed Profiles"),
                    footer: wtLang.tr("Parsed from the .plist files in the ConfigurationProfiles directory. This page never installs or removes a profile.")
                ) {
                    if viewer.records.isEmpty {
                        Text(wtLang.tr("No installable profile records were found in this directory."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(viewer.records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.displayName ?? record.fileName)
                                        .font(.subheadline.weight(.semibold))
                                    if let identifier = record.identifier {
                                        Text(identifier)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    if let org = record.organization {
                                        Text(org)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let description = record.description {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(record.fileName)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                WTSectionCard(header: wtLang.tr("Files in ConfigurationProfiles")) {
                    if viewer.files.isEmpty {
                        Text(wtLang.tr("The directory is empty."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(viewer.files.enumerated()), id: \.element.id) { index, file in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                HStack(spacing: 10) {
                                    RowIcon(systemImage: "doc")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name)
                                            .font(.subheadline)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let modified = file.modified {
                                            Text(modified, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Text(wtFormatSize(file.size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(wtLang.tr("Configuration Profiles"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewer.load()
        }
    }

    private func supervisionTitle(_ state: ProfileAudit.State) -> String {
        switch state {
        case .clean: return wtLang.tr("Not Supervised")
        case .genuineMDM: return wtLang.tr("Genuine MDM")
        case .fakeResidue: return wtLang.tr("Fake-Supervision Residue")
        }
    }

    private func supervisionIcon(_ state: ProfileAudit.State) -> String {
        switch state {
        case .clean: return "checkmark.seal.fill"
        case .genuineMDM: return "building.2.fill"
        case .fakeResidue: return "exclamationmark.triangle.fill"
        }
    }

    private func supervisionColor(_ state: ProfileAudit.State) -> Color {
        switch state {
        case .clean: return .green
        case .genuineMDM: return .accentColor
        case .fakeResidue: return .orange
        }
    }
}
