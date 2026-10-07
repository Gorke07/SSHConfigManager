import Foundation

/// Stable identity of a sidebar row. Hosts are identified by alias + occurrence, not by line
/// number, so edits above a host do not change which row is selected.
enum SidebarItem: Hashable, Sendable {
    case host(alias: String, occurrence: Int)
    case included(id: String)
    case match(index: Int)
}
