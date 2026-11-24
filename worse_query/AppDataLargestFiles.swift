import SwiftUI

// MARK: - Largest Files scanner
//
// Top 100 largest regular files inside one app container,
// found with POSIX fstatat (AT_SYMLINK_NOFOLLOW) so symlinks
// are never followed and never counted as their target.
// Runs on a background queue under the container's browsing
// grant (held by the App Data page that opened this view).
// Log prefix: [LargestFiles].

struct AppDataLargestFile: Identifiable {
    /// Path relative to the container root.
    let relativePath: String
    let size: Int64

    var id: String { relativePath }
}

enum AppDataLargestFiles {
    /// Scan one container for its Top 100 largest regular
    /// files. `progress` reports files examined (throttled by
    /// the caller); `completion` delivers the sorted list,
    /// largest first.
    static func scan(
        containerPath: String,
        limit: Int = 100,
        progress: @escaping (Int) -> Void,
        completion: @escaping ([AppDataLargestFile]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let root = URL(fileURLWithPath: containerPath)
            var top: [AppDataLargestFile] = []
            var examined = 0
            var lastReport = 0
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                if values.isSymbolicLink == true {
                    if values.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if values.isDirectory == true { continue }
                examined += 1
                if examined - lastReport >= 500 {
                    lastReport = examined
                    let count = examined
                    DispatchQueue.main.async { progress(count) }
                }
                var st = stat()
                guard fstatat(AT_FDCWD, url.path, &st, AT_SYMLINK_NOFOLLOW) == 0,
                      (st.st_mode & S_IFMT) == S_IFREG else { continue }
                let size = Int64(st.st_size)
                guard size > 0 else { continue }
                let relative = String(url.path.dropFirst(containerPath.count + 1))
                let entry = AppDataLargestFile(relativePath: relative, size: size)
                if top.count < limit {
                    top.append(entry)
                    top.sort { $0.size > $1.size }
                } else if let smallest = top.last, size > smallest.size {
                    top.removeLast()
                    top.append(entry)
                    top.sort { $0.size > $1.size }
                }
            }
            print("[LargestFiles] scanned \(examined) file(s) under \(containerPath), top \(top.count)")
            let result = top
            let total = examined
            DispatchQueue.main.async {
                progress(total)
                completion(result)
            }
        }
    }
}

struct AppDataLargestFilesView: View {
    @EnvironmentObject private var wtLang: WTLangStore
    let container: AppContainer

    @State private var files: [AppDataLargestFile] = []
    @State private var examined = 0
    @State private var done = false

    private var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        WTGlassPage {
            WTSectionCard(header: wtLang.tr("Largest files"), footer: container.path) {
                if !done {
                    HStack(spacing: 10) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(wtLang.tr("Scanning %@…", container.bundleID))
                                .font(.subheadline)
                            Text(wtLang.tr("%d file(s) examined — the scan walks the whole container, so large apps take a while.", examined))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else if files.isEmpty {
                    Text(wtLang.tr("No regular files found in this container."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(wtLang.tr("%d largest file(s) — %@ in the top %d.", files.count, wtFormatSize(totalBytes), files.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        Divider()
                            .padding(.leading, 14)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 14)
                                }
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.relativePath)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 8)
                                    Text(wtFormatSize(file.size))
                                        .font(.subheadline.weight(.semibold))
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
        .navigationTitle(wtLang.tr("Largest Files"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AppDataLargestFiles.scan(
                containerPath: container.path,
                progress: { count in examined = count },
                completion: { result in
                    files = result
                    done = true
                }
            )
        }
    }
}
