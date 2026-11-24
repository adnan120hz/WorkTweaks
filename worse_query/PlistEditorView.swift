import SwiftUI

// MARK: - Property list editor (view)
//
// Key/type/value table of the plist's top level. Tapping an
// editable scalar opens the edit sheet (type-validated);
// containers and Data are shown read-only. Add Row and
// Delete complete the table editing; Save rebuilds the plist
// and writes it back in place after a pristine backup (see
// PlistEditor.swift).

struct PlistEditorView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var manager: AppDataManager
    let path: String
    let name: String

    @StateObject private var editor = PlistEditor()
    @State private var editingRow: PlistRow?
    @State private var showAddRow = false
    @State private var showDeleteConfirm: PlistRow?

    var body: some View {
        WTGlassPage {
            switch editor.state {
            case .idle, .loading:
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(wtLang.tr("Reading the property list…"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            case .blocked(let message):
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(wtLang.tr("Couldn't open this property list."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            case .ready:
                WTSectionCard(
                    header: editor.rootKind == .dictionary ? wtLang.tr("Keys") : wtLang.tr("Elements"),
                    footer: wtLang.tr("Nested dictionaries, arrays and Data are shown read-only — the editor never rewrites a structure it cannot show.")
                ) {
                    if editor.rows.isEmpty {
                        Text(wtLang.tr("This property list has no top-level entries."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(editor.rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                rowView(row)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                WTSectionCard(footer: wtLang.tr("Saving rebuilds the property list from this table, takes a backup of the original first, then writes it back in place. Close the owning app before saving — a running app can overwrite your edits.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            showAddRow = true
                        } label: {
                            Label(wtLang.tr("Add Row"), systemImage: "plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                        Divider()
                            .padding(.leading, 14)
                        Button {
                            editor.save(manager: manager)
                        } label: {
                            Text(editor.isSaving ? wtLang.tr("Saving…") : (editor.isDirty ? wtLang.tr("Save") : wtLang.tr("Saved")))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                        .disabled(!editor.isDirty || editor.isSaving)
                    }
                }

                if let message = editor.saveMessage {
                    WTSectionCard {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(editor.saveFailed ? .orange : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRow) { row in
            PlistRowEditSheet(editor: editor, row: row)
        }
        .sheet(isPresented: $showAddRow) {
            PlistRowAddSheet(editor: editor)
        }
        .confirmationDialog(wtLang.tr("Delete this row?"), isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button(wtLang.tr("Delete Row"), role: .destructive) {
                if let row = showDeleteConfirm {
                    editor.deleteRow(row)
                }
                showDeleteConfirm = nil
            }
            Button(wtLang.tr("Cancel"), role: .cancel) { showDeleteConfirm = nil }
        } message: {
            Text(wtLang.tr("The entry is removed from the property list on the next Save."))
        }
        .onAppear {
            if case .idle = editor.state {
                editor.open(path: path, name: name)
            }
        }
    }

    private func rowView(_ row: PlistRow) -> some View {
        HStack(spacing: 10) {
            Button {
                guard row.isEditable else { return }
                editingRow = row
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.key)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.display)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(row.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        )
                    if row.isEditable {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!row.isEditable)
            Button(role: .destructive) {
                showDeleteConfirm = row
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .padding(.trailing, 14)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Row edit sheet

private struct PlistRowEditSheet: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var editor: PlistEditor
    let row: PlistRow

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            WTGlassPage {
                WTSectionCard(header: row.key, footer: wtLang.tr("Type: %@. %@", row.kind.rawValue, hint)) {
                    TextField(wtLang.tr("Value"), text: $text)
                        .font(.system(.body, design: .monospaced))
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                }

                if let error {
                    WTSectionCard {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                WTSectionCard {
                    Button {
                        if let message = editor.applyEdit(rowID: row.id, text: text) {
                            error = message
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(wtLang.tr("Apply Edit"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle(wtLang.tr("Edit Value"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            text = row.display
        }
    }

    private var hint: String {
        switch row.kind {
        case .integer: return wtLang.tr("Whole numbers only.")
        case .real: return wtLang.tr("Numbers only.")
        case .bool: return wtLang.tr("true or false.")
        case .date: return wtLang.tr("ISO date (e.g. 2026-11-24T15:30:00Z) or yyyy-MM-dd HH:mm:ss.")
        default: return ""
        }
    }
}

// MARK: - Add row sheet

private struct PlistRowAddSheet: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var editor: PlistEditor

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var kind: PlistValueKind = .string
    @State private var text = ""
    @State private var error: String?

    private var scalarKinds: [PlistValueKind] { [.string, .integer, .real, .bool, .date] }

    var body: some View {
        NavigationStack {
            WTGlassPage {
                WTSectionCard(header: wtLang.tr("New Row")) {
                    VStack(alignment: .leading, spacing: 0) {
                        if editor.rootKind == .dictionary {
                            TextField(wtLang.tr("Key"), text: $key)
                                .disableAutocorrection(true)
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            Divider()
                                .padding(.leading, 14)
                        }
                        Picker(wtLang.tr("Type"), selection: $kind) {
                            ForEach(scalarKinds, id: \.self) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        Divider()
                            .padding(.leading, 14)
                        TextField(wtLang.tr("Value"), text: $text)
                            .font(.system(.body, design: .monospaced))
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    }
                }

                if let error {
                    WTSectionCard {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }

                WTSectionCard {
                    Button {
                        if let message = editor.addRow(key: key, kind: kind, text: text) {
                            error = message
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(wtLang.tr("Add Row"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle(wtLang.tr("Add Row"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Cancel")) { dismiss() }
                }
            }
        }
    }
}
