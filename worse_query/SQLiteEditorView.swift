import SwiftUI

// MARK: - SQLite table editor (view)
//
// Table picker, a horizontally scrolling grid of the first
// 200 rows, tap-a-cell editing (text / integer / real with
// type validation, NULL via the Set NULL button), add and
// delete rows, and Save — which applies the edits through
// SQLite on the clone and writes the clone back over the
// original (see SQLiteEditor.swift). BLOB cells are shown
// read-only; the editor never lets a binary value be typed.

struct SQLiteEditorView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var manager: AppDataManager
    let path: String
    let name: String

    @StateObject private var editor = SQLiteDatabaseEditor()
    @State private var editingCell: SQLiteCellRef?
    @State private var showDeleteConfirm: SQLiteTableRow?

    var body: some View {
        WTGlassPage {
            switch editor.state {
            case .idle, .loading:
                WTSectionCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(wtLang.tr("Opening the database…"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            case .blocked(let message):
                WTSectionCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(wtLang.tr("Couldn't open this database."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            case .ready:
                if editor.tables.count > 1 {
                    WTSectionCard(header: wtLang.tr("Table")) {
                        Picker(wtLang.tr("Table"), selection: Binding(
                            get: { editor.selectedTable ?? "" },
                            set: { editor.selectTable($0) }
                        )) {
                            ForEach(editor.tables, id: \.self) { table in
                                Text(table).tag(table)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }

                if editor.columns.isEmpty {
                    WTSectionCard {
                        Text(wtLang.tr("This table has no columns to edit."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                } else {
                    WTSectionCard(
                        header: editor.selectedTable ?? "",
                        footer: editor.totalRowCount > Int64(SQLiteDatabaseEditor.rowLimit)
                            ? wtLang.tr("Showing the first %@ of %@ rows — the editor is for targeted edits, not bulk dumps.", "\(SQLiteDatabaseEditor.rowLimit)", "\(editor.totalRowCount)")
                            : wtLang.tr("%d row(s).", editor.rows.count)
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                // Header row.
                                HStack(spacing: 0) {
                                    Text("rowid")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .leading)
                                    ForEach(editor.columns) { column in
                                        Text(column.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 110, alignment: .leading)
                                    }
                                    Spacer(minLength: 40)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                Divider()
                                ForEach(Array(editor.rows.enumerated()), id: \.element.id) { rowIndex, row in
                                    dataRow(rowIndex: rowIndex, row: row)
                                    if rowIndex < editor.rows.count - 1 {
                                        Divider()
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                WTSectionCard(footer: wtLang.tr("Saving applies the edits to the database through SQLite, takes a backup of the original first, then writes the edited file back in place. Close the owning app before saving — a running app can overwrite your edits.")) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            editor.addRow()
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
        .sheet(item: $editingCell) { ref in
            SQLiteCellEditSheet(editor: editor, ref: ref)
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
            Text(wtLang.tr("The row is deleted from the database on the next Save."))
        }
        .onAppear {
            if case .idle = editor.state {
                editor.open(path: path, name: name)
            }
        }
    }

    /// One data row, extracted so the page body stays small
    /// enough for the type-checker.
    private func dataRow(rowIndex: Int, row: SQLiteTableRow) -> some View {
        HStack(spacing: 0) {
            Text("\(row.rowid)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            ForEach(Array(editor.columns.enumerated()), id: \.offset) { colIndex, column in
                cellView(rowIndex: rowIndex, colIndex: colIndex, column: column)
            }
            Button(role: .destructive) {
                showDeleteConfirm = row
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func cellView(rowIndex: Int, colIndex: Int, column: SQLiteColumn) -> some View {
        let cell = editor.rows[rowIndex].values[colIndex]
        let isChanged = editor.rows[rowIndex].values[colIndex] != originalCell(rowIndex: rowIndex, colIndex: colIndex)
        return Button {
            guard column.isEditable else { return }
            editingCell = SQLiteCellRef(rowIndex: rowIndex, colIndex: colIndex)
        } label: {
            Text(cell.display)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(cell.isNull ? Color.secondary : (isChanged ? Color.orange : Color.primary))
                .frame(minWidth: 110, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!column.isEditable)
    }

    /// The cell's value as loaded, for the changed highlight.
    /// The editor keeps the loaded snapshot beside the rows.
    private func originalCell(rowIndex: Int, colIndex: Int) -> SQLiteCell {
        // The rows array is replaced wholesale on every
        // reload; while editing, the loaded snapshot lives in
        // the editor's originalRows — exposed here through a
        // lookup by rowid so the highlight survives sorting.
        editor.originalCell(rowid: editor.rows[rowIndex].rowid, colIndex: colIndex) ?? editor.rows[rowIndex].values[colIndex]
    }
}

private struct SQLiteCellRef: Identifiable {
    let id = UUID()
    let rowIndex: Int
    let colIndex: Int
}

// MARK: - Cell edit sheet

private struct SQLiteCellEditSheet: View {
    @EnvironmentObject private var wtLang: WTLangStore
    @ObservedObject var editor: SQLiteDatabaseEditor
    let ref: SQLiteCellRef

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isNull = false

    private var column: SQLiteColumn { editor.columns[ref.colIndex] }
    private var current: SQLiteCell { editor.rows[ref.rowIndex].values[ref.colIndex] }

    var body: some View {
        NavigationStack {
            WTGlassPage {
                WTSectionCard(header: column.name, footer: wtLang.tr("Type: %@ (%@). %@", column.type.isEmpty ? "—" : column.type, column.affinity.lowercased(), column.affinity == "INTEGER" ? wtLang.tr("Whole numbers only.") : column.affinity == "REAL" ? wtLang.tr("Numbers only.") : wtLang.tr("Stored as text."))) {
                    VStack(alignment: .leading, spacing: 0) {
                        if isNull {
                            Text("NULL")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                        } else {
                            TextField(wtLang.tr("Value"), text: $text)
                                .font(.system(.body, design: .monospaced))
                                .disableAutocorrection(true)
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                        }
                        Divider()
                            .padding(.leading, 14)
                        Button {
                            isNull.toggle()
                            if !isNull, text.isEmpty { text = current.text ?? "" }
                        } label: {
                            Text(isNull ? wtLang.tr("Clear NULL (edit a value)") : wtLang.tr("Set NULL"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                        }
                    }
                }

                WTSectionCard {
                    Button {
                        editor.rows[ref.rowIndex].values[ref.colIndex] = SQLiteCell(text: isNull ? nil : text)
                        dismiss()
                    } label: {
                        Text(wtLang.tr("Apply Edit"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .disabled(!isNull && text == (current.text ?? ""))
                }
            }
            .navigationTitle(wtLang.tr("Edit Cell"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(wtLang.tr("Cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            text = current.text ?? ""
            isNull = current.text == nil
        }
    }
}
