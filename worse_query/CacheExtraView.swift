import SwiftUI

// MARK: - Extra tab: free-form CacheExtra editor
//
// In the spirit of mond's CEView: the core system gives raw access to
// MobileGestalt, so users can type ANY CacheExtra key and value here —
// add new keys, edit values, delete keys. Edits are staged in the same
// in-memory dictionary the tweak toggles use; "Apply Tweaks" in the
// Tweaks tab writes them to disk (with the Respring / Restart choice).

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

    var body: some View {
        let _ = manager.dictVersion // re-render when the dict changes
        NavigationStack {
            List {
                Section {
                    Text("Type any CacheExtra key and value — the core system exposes the raw MobileGestalt dictionary. Edits are staged in memory like the tweak toggles: press **Apply Tweaks** in the Tweaks tab to write them (you'll get the Respring / Restart choice).")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !manager.isValid {
                    Section {
                        Label("MobileGestalt is not loaded yet — keys are unavailable.", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                    }
                } else {
                    Section {
                        ForEach(filteredKeys, id: \.self) { key in
                            Button { editing = KeyRef(key: key) } label: {
                                row(for: key)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    manager.removeExtraKey(key)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("CacheExtra Keys (\(filteredKeys.count))")
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
            Text(ExtraValueKind.of(value) ?.rawValue ?? "Complex")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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
            Form {
                Section {
                    if let existingKey {
                        Text(existingKey)
                            .font(.system(.footnote, design: .monospaced))
                    } else {
                        TextField("Key (e.g. CacheExtra style name)", text: $keyText)
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Key")
                }

                if let complexDescription {
                    Section {
                        Text(complexDescription)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Value (complex — read-only)")
                    } footer: {
                        Text("Arrays, dictionaries and data can't be typed in here. You can still delete this key.")
                    }
                } else {
                    Section {
                        Picker("Type", selection: $kind) {
                            ForEach(ExtraValueKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch kind {
                        case .string:
                            TextField("Text value", text: $textValue)
                                .autocorrectionDisabled()
                        case .integer:
                            TextField("Integer value (e.g. 1)", text: $textValue)
                                .keyboardType(.numbersAndPunctuation)
                                .autocorrectionDisabled()
                        case .double:
                            TextField("Double value (e.g. 1.5)", text: $textValue)
                                .keyboardType(.decimalPad)
                                .autocorrectionDisabled()
                        case .boolean:
                            Toggle("Value", isOn: $boolValue)
                        }
                    } header: {
                        Text("Value")
                    } footer: {
                        Text("String = free text. Integer / Double = numbers. Boolean = true/false switch.")
                    }
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }

                if existingKey != nil {
                    Section {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete Key", systemImage: "trash")
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
