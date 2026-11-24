import Foundation
import Combine
import Darwin

// MARK: - Configuration profile viewer (read-only)
//
// Lists the installed configuration profiles and the
// supervision state from
// systemgroup.com.apple.configurationprofiles — the same
// directory the Lock Screen footnote reads. READ-ONLY by
// design: nothing here is ever written, installed or
// removed.
//
// The supervision audit follows Erosion-CN's ConfigView
// (see License & Credits): a CloudConfigurationDetails.plist
// that only says IsSupervised + OrganizationName — with no
// genuine-MDM key (ConfigurationSource,
// PostSetupProfileWasInstalled, AwaitDeviceConfigured,
// CloudConfigurationUIComplete, ConfigurationURL,
// AnchorCertificates, SupervisorHostCertificates) — is
// fake-supervision residue, not real MDM. Real MDM is
// protected and shown as such. There is NO supervision
// toggle here: writing IsSupervised=true on a retail device
// can trap Setup.app in an infinite remote-management loop
// (never reaching the Home Screen), so that path is
// permanently excluded.
//
// Every step logs with a [Profiles] prefix.

struct ProfileFileEntry: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let modified: Date?
}

/// One parsed profile record from a .plist in the
/// ConfigurationProfiles directory.
struct ProfileRecord: Identifiable {
    let id = UUID()
    let fileName: String
    let displayName: String?
    let identifier: String?
    let uuid: String?
    let organization: String?
    let description: String?
}

struct ProfileAudit {
    enum State {
        case clean
        case genuineMDM
        case fakeResidue
    }

    let state: State
    let isSupervised: Bool
    let organizationName: String?
    let footnote: String?
    let assetTag: String?
    let detail: String
}

final class ProfileViewer: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case ready
        case blocked(String)
    }

    static let directoryPath = FootnoteManager.directoryPath

    /// Keys whose presence means the cloud configuration is
    /// genuine MDM, not a fake-supervision leftover.
    static let genuineMDMKeys: Set<String> = [
        "ConfigurationSource",
        "PostSetupProfileWasInstalled",
        "AwaitDeviceConfigured",
        "CloudConfigurationUIComplete",
        "ConfigurationURL",
        "AnchorCertificates",
        "SupervisorHostCertificates",
    ]

    @Published var state: LoadState = .idle
    @Published var audit: ProfileAudit?
    @Published var records: [ProfileRecord] = []
    @Published var files: [ProfileFileEntry] = []

    func load() {
        guard case .idle = state else { return }
        state = .loading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performLoad()
        }
    }

    private func performLoad() {
        print("[Profiles] loading \(Self.directoryPath)")
        let handle = consumeExtension(Self.directoryPath)
        print("[Profiles] grant -> \(handle)")
        guard handle > 0 else {
            finishBlocked("The sandbox extension for the ConfigurationProfiles directory was refused (code \(handle)). Nothing was read or written — the exact grant result is in the Log.")
            return
        }
        defer { releaseExtension(handle) }

        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Self.directoryPath) else {
            finishBlocked("The ConfigurationProfiles directory could not be listed. Nothing was read or written.")
            return
        }

        var fileEntries: [ProfileFileEntry] = []
        for name in names.sorted() {
            let full = (Self.directoryPath as NSString).appendingPathComponent(name)
            var size: Int64 = 0
            var modified: Date?
            if let attrs = try? fm.attributesOfItem(atPath: full) {
                size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                modified = attrs[.modificationDate] as? Date
            }
            fileEntries.append(ProfileFileEntry(name: name, size: size, modified: modified))
        }

        var footnote: String?
        var assetTag: String?
        if let shared = readPlist("SharedDeviceConfiguration.plist") {
            footnote = shared["LockScreenFootnote"] as? String
            if let tag = shared["AssetTagInformation"] as? [String: Any] {
                assetTag = tag["AssetTag"] as? String ?? tag["AssetTagInfo"] as? String
            } else if let tag = shared["AssetTag"] as? String {
                assetTag = tag
            }
        }

        var auditState: ProfileAudit.State = .clean
        var isSupervised = false
        var orgName: String?
        var auditDetail = "No CloudConfigurationDetails.plist — the device is not supervised."
        if let cloud = readPlist("CloudConfigurationDetails.plist") {
            isSupervised = (cloud["IsSupervised"] as? Bool) ?? false
            orgName = cloud["OrganizationName"] as? String
            let keys = Set(cloud.keys)
            let hasGenuineKey = !keys.isDisjoint(with: Self.genuineMDMKeys)
            let hasOtherKey = keys.subtracting(["IsSupervised", "OrganizationName"]).count > 0
            if hasGenuineKey || hasOtherKey {
                auditState = .genuineMDM
                auditDetail = "Genuine MDM enrollment — this configuration is managed by an organization and is protected. Nothing here can change it."
            } else if isSupervised {
                auditState = .fakeResidue
                auditDetail = "This file only claims IsSupervised + an organization name, with no genuine-MDM key — it is fake-supervision residue left by another tool, not real MDM. It is shown read-only here; removing it is not offered on this page."
            } else {
                auditDetail = "CloudConfigurationDetails.plist exists but does not claim supervision."
            }
        }

        var parsedRecords: [ProfileRecord] = []
        for entry in fileEntries where entry.name.hasSuffix(".plist") {
            guard let dict = readPlist(entry.name) else { continue }
            // Skip the two files already shown in the audit.
            if entry.name == "SharedDeviceConfiguration.plist" || entry.name == "CloudConfigurationDetails.plist" {
                continue
            }
            parsedRecords.append(ProfileRecord(
                fileName: entry.name,
                displayName: dict["PayloadDisplayName"] as? String,
                identifier: dict["PayloadIdentifier"] as? String,
                uuid: dict["PayloadUUID"] as? String,
                organization: dict["PayloadOrganization"] as? String,
                description: dict["PayloadDescription"] as? String
            ))
        }

        let audit = ProfileAudit(
            state: auditState,
            isSupervised: isSupervised,
            organizationName: orgName,
            footnote: footnote,
            assetTag: assetTag,
            detail: auditDetail
        )
        print("[Profiles] \(fileEntries.count) file(s), \(parsedRecords.count) profile record(s), supervision: \(auditState)")
        DispatchQueue.main.async {
            self.files = fileEntries
            self.records = parsedRecords
            self.audit = audit
            self.state = .ready
        }
    }

    private func finishBlocked(_ message: String) {
        print("[Profiles] blocked: \(message)")
        DispatchQueue.main.async { self.state = .blocked(message) }
    }

    private func readPlist(_ name: String) -> [String: Any]? {
        let path = (Self.directoryPath as NSString).appendingPathComponent(name)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }
}
