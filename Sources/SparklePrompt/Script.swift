import Foundation

struct Workspace: Identifiable, Equatable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var scripts: [Script]
    var isExpanded: Bool = true
    var folderURL: URL?          // 兼容旧数据 & 运行时解析后的 URL
    var folderBookmark: Data?    // ✨ 持久化的文件夹引用（Bookmark）

    /// 通过 Bookmark 解析文件夹的当前位置，自动处理重命名/移动
    mutating func resolveFolderURL() -> URL? {
        // 优先使用 Bookmark
        if let data = folderBookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                folderURL = resolved
                if isStale {
                    folderBookmark = try? resolved.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
                return resolved
            }
        }
        // 降级使用 URL（兼容旧数据）
        return folderURL
    }

    /// 检查关联的物理文件夹是否仍然存在于磁盘上（更智能的判定）
    var isFolderMissing: Bool {
        guard folderURL != nil || folderBookmark != nil else { return false }

        // 1. 如果当前的 URL 还在，直接返回
        if let url = folderURL {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return false
            }
        }

        // 2. 如果当前 URL 失效，尝试用 Bookmark 默默解析一下（不更新状态，仅做判定）
        if let data = folderBookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue {
                    return false // 物理实体还在，只是路径变了，不属于 Missing
                }
            }
        }

        return true
    }

    /// 创建 Workspace 时自动生成 Bookmark
    init(id: UUID = UUID(), name: String, scripts: [Script], isExpanded: Bool = true, folderURL: URL? = nil) {
        self.id = id
        self.name = name
        self.scripts = scripts
        self.isExpanded = isExpanded
        self.folderURL = folderURL
        if let url = folderURL {
            self.folderBookmark = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }
}

/// A single script/document in the library.
struct Script: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var title: String
    var content: String
    var url: URL?              // 运行时解析后的 URL
    var bookmarkData: Data?    // ✨ 持久化的文件引用（Bookmark）
    var lastScrollOffset: CGFloat = 0
    var isAIGenerated: Bool = false
    var lastModifiedDate: Date?
    var isTitleCustomized: Bool = false // ✨ 标识用户是否手动修改过标题

    init(id: UUID = UUID(), title: String, content: String, url: URL? = nil, isAIGenerated: Bool = false, lastModifiedDate: Date? = nil, isTitleCustomized: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.url = url
        self.isAIGenerated = isAIGenerated
        self.lastModifiedDate = lastModifiedDate
        self.isTitleCustomized = isTitleCustomized
        // 自动为本地文件生成 Bookmark
        if let url = url, !isAIGenerated {
            self.bookmarkData = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    /// 通过 Bookmark 解析文件的当前位置
    mutating func resolveURL() -> URL? {
        if let data = bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                url = resolved
                if isStale {
                    bookmarkData = try? resolved.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
                return resolved
            }
        }
        return url
    }

    /// Create a Script by reading a text file from disk.
    static func fromFile(_ url: URL) -> Script? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let modDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return Script(
            title: url.deletingPathExtension().lastPathComponent,
            content: content,
            url: url,
            lastModifiedDate: modDate
        )
    }

    /// Create a lightweight Script reference without loading file contents.
    static func metadataFromFile(_ url: URL) -> Script? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        let modDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return Script(
            title: url.deletingPathExtension().lastPathComponent,
            content: "",
            url: url,
            lastModifiedDate: modDate
        )
    }

    static func == (lhs: Script, rhs: Script) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func matchesLibrarySearch(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) ||
            content.localizedCaseInsensitiveContains(query)
    }
}
