import Foundation

struct LibraryMoveTarget: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let name: String
    let usesFolderIcon: Bool
}

struct LibraryScriptRowData: Identifiable, Equatable {
    let id: UUID
    let originalIndex: Int
    let title: String
    let contentCharacterCount: Int
    let isAIGenerated: Bool
    let isSelected: Bool
}

struct LibraryWorkspaceSection: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let name: String
    let isExpanded: Bool
    let isFolderMissing: Bool
    let hasFolderURL: Bool
    let isActive: Bool
    let showsScripts: Bool
    let isEmpty: Bool
    let scripts: [LibraryScriptRowData]
}
