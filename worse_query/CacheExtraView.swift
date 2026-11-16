import SwiftUI

// MARK: - Extra tab: free-form CacheExtra editor
//
// In the spirit of mond's CEView: the core system gives raw access to
// MobileGestalt, so users can type ANY CacheExtra key and value here —
// add new keys, edit values, delete keys. Edits are staged in the same
// in-memory dictionary the tweak toggles use; "Apply Tweaks" in the
// Tweaks tab writes them to disk (with the Respring / Restart choice).
//
// Since v3.8 the tab renders as Liquid Glass cards (WTGlassPage),
// like every other page. The List's swipe-to-delete becomes a
// long-press context menu on each key row — same immediate delete,
// same editor, same add flow.

enum ExtraValueKind: String, CaseIterable, Identifiable {
    case string = "String"
    case integer = "Integer"
    case double = "Double"
    case boolean = "Boolean"

    var id: String { rawValue }

    /// Classifies a plist value; nil = complex (array/dict/data), which
    /// is shown read-only.
    static func of(_ value: Any) -> ExtraValueKind? {
        if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return .boolean }
        if let number = value as? NSNumber {
            let d = number.doubleValue
            return (d == Double(number.int64Value) && abs(d) < 9.0e15) ? .integer : .double
        }
        if value is String { return .string }
        return nil
    }
}

private struct KeyRef: Identifiable {
    let key: String
    var id: String { key }
}

struct CacheExtraView: View {
    @ObservedObject var manager: GestaltManager

    @State private var search = ""
    @State private var editing: KeyRef?
    @State private var showAdd = false
    @State private var showResetConfirm = false

    var body: some View {
        let _ = manager.dictVersion // re-render when the dict changes
        NavigationStack {
            WTGlassPage {
                WTSectionCard {
                    Text("Type any CacheExtra key and value — the core system exposes the raw MobileGestalt dictionary. Edits are staged in memory like the tweak toggles: press **Apply Tweaks** in the Tweaks tab to write them (you'll get the Respring / Restart choice).")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                if !manager.isValid {
                    WTSectionCard {
                        Label("MobileGestalt is not loaded yet — keys are unavailable.", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                } else {
                    WTSectionCard(header: "CacheExtra Keys (\(filteredKeys.count))") {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filteredKeys.enumerated()), id: \.element) { index, key in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                Button { editing = KeyRef(key: key) } label: {
                                    row(for: key)
                                        .padding(.horizontal, 14)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        manager.removeExtraKey(key)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if manager.isValid {
                    WTSectionCard(footer: "Undoes everything changed or added in this tab: edited and deleted keys return to the values they had when MobileGestalt was loaded, and added keys disappear. Tweak states are not affected, and — like the edits — the reset is only written when you press Apply Tweaks.") {
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Label("Reset Extra", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle("Cache Extra")
            .searchable(text: $search, prompt: "Search keys")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!manager.isValid)
                }
            }
            .sheet(isPresented: $showAdd) {
                ExtraKeyEditor(manager: manager, existingKey: nil)
            }
            .sheet(item: $editing) { ref in
                ExtraKeyEditor(manager: manager, existingKey: ref.key)
            }
            .confirmationDialog("Reset Extra?", isPresented: $showResetConfirm) {
                Button("Reset Extra", role: .destructive) { manager.resetExtraEdits() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("All changes and additions made in the Extra tab will be removed, and edited keys return to the values they had when MobileGestalt was loaded. Tweak states are not affected. The reset takes effect when you press Apply Tweaks.")
            }
        }
    }

    private var filteredKeys: [String] {
        guard let extra = manager.cacheExtra else { return [] }
        let keys = extra.allKeys.compactMap { $0 as? String }.sorted()
        guard !search.isEmpty else { return keys }
        return keys.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private func row(for key: String) -> some View {
        let value = manager.cacheExtra?[key] ?? "—"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(PlistValue.describe(value as Any))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Text(ExtraValueKind.of(value)?.rawValue ?? "Complex")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add / edit sheet

struct ExtraKeyEditor: View {
    @ObservedObject var manager: GestaltManager
    let existingKey: String?

    @Environment(\.dismiss) private var dismiss

    @State private var keyText = ""
    @State private var kind: ExtraValueKind = .string
    @State private var textValue = ""
    @State private var boolValue = false
    @State private var complexDescription: String?
    @State private var errorText: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            WTGlassPage {
                WTSectionCard(header: "Key") {
                    if let existingKey {
                        Text(existingKey)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    } else {
                        TextField("Key (e.g. CacheExtra style name)", text: $keyText)
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    }
                }

                if let complexDescription {
                    WTSectionCard(header: "Value (complex — read-only)", footer: "Arrays, dictionaries and data can't be typed in here. You can still delete this key.") {
                        Text(complexDescription)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    }
                } else {
                    WTSectionCard(header: "Value", footer: "String = free text. Integer / Double = numbers. Boolean = true/false switch.") {
                        VStack(alignment: .leading, spacing: 0) {
                            Picker("Type", selection: $kind) {
                                ForEach(ExtraValueKind.allCases) { k in
                                    Text(k.rawValue).tag(k)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                            Divider()
                                .padding(.leading, 14)

                            switch kind {
                            case .string:
                                TextField("Text value", text: $textValue)
                                    .autocorrectionDisabled()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                            case .integer:
                                TextField("Integer value (e.g. 1)", text: $textValue)
                                    .keyboardType(.numbersAndPunctuation)
                                    .autocorrectionDisabled()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                            case .double:
                                TextField("Double value (e.g. 1.5)", text: $textValue)
                                    .keyboardType(.decimalPad)
                                    .autocorrectionDisabled()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                            case .boolean:
                                Toggle("Value", isOn: $boolValue)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }

                if let errorText {
                    WTSectionCard {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                if existingKey != nil {
                    WTSectionCard {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete Key", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle(existingKey == nil ? "Add Key" : "Edit Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if complexDescription == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                    }
                }
            }
            .confirmationDialog("Delete this key?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let existingKey { manager.removeExtraKey(existingKey) }
                    dismiss()
                }
            } message: {
                Text("The key is removed from the staged dictionary. The change is written when you press Apply Tweaks.")
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let existingKey, let value = manager.cacheExtra?[existingKey] else { return }
        keyText = existingKey
        if let k = ExtraValueKind.of(value) {
            kind = k
            switch k {
            case .string: textValue = value as? String ?? ""
            case .integer: textValue = (value as? NSNumber)?.stringValue ?? ""
            case .double: textValue = (value as? NSNumber)?.stringValue ?? ""
            case .boolean: boolValue = (value as? NSNumber)?.boolValue ?? false
            }
        } else {
            complexDescription = PlistValue.describe(value)
        }
    }

    private func save() {
        let key = (existingKey ?? keyText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = "Key cannot be empty."
            return
        }
        if existingKey == nil, manager.cacheExtra?[key] != nil {
            errorText = "That key already exists — edit it from the list instead."
            return
        }

        let value: Any
        switch kind {
        case .string:
            value = textValue
        case .integer:
            guard let n = Int64(textValue.trimmingCharacters(in: .whitespaces)) else {
                errorText = "\"\(textValue)\" is not a valid integer."
                return
            }
            value = NSNumber(value: n)
        case .double:
            guard let n = Double(textValue.trimmingCharacters(in: .whitespaces)) else {
                errorText = "\"\(textValue)\" is not a valid double."
                return
            }
            value = NSNumber(value: n)
        case .boolean:
            value = NSNumber(value: boolValue)
        }

        manager.setExtraValue(value, forKey: key)
        dismiss()
    }
}
