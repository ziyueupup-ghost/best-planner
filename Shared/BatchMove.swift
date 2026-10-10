import Foundation

// Moving several selected tasks at once. Selected tasks always move as a block and
// keep their relative order (board order: column by column, top to bottom).

enum TaskPlacement: Equatable {
    case top
    case bottom
    case before(String)
}

extension Board {
    /// The given ids in board order.
    func orderedIDs(_ ids: Set<String>) -> [String] {
        columns.flatMap { tasks(in: $0.id) }.map(\.id).filter(ids.contains)
    }

    /// Gives tasks consecutive order values matching the list (doesn't touch history).
    mutating func renumber(_ list: [PlannerTask]) {
        for (n, t) in list.enumerated() {
            if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i].order = Double(n) }
        }
    }

    /// Moves tasks into a column (recording status changes in history) and places them
    /// there as one block.
    mutating func moveTasks(_ ids: Set<String>, to columnID: String, placement: TaskPlacement) {
        guard column(columnID) != nil else { return }
        let moving = orderedIDs(ids)
        guard !moving.isEmpty else { return }
        for id in moving {
            guard let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].columnID != columnID else { continue }
            let old = tasks[i]
            var t = old
            t.columnID = columnID
            record(from: old, to: &t, oldColumns: columns)
            t.updatedAt = Date()
            tasks[i] = t
        }
        var list = self.tasks(in: columnID).filter { !ids.contains($0.id) }
        let index: Int
        switch placement {
        case .top: index = 0
        case .bottom: index = list.count
        case .before(let target): index = list.firstIndex { $0.id == target } ?? list.count
        }
        let block = moving.compactMap { id in tasks.first { $0.id == id } }
        list.insert(contentsOf: block, at: index)
        renumber(list)
    }

    /// Moves each selected task up (-1) or down (+1) one place within its column,
    /// stepping over unselected neighbours; a block at the edge stays put.
    mutating func shiftTasks(_ ids: Set<String>, by offset: Int) {
        for column in columns {
            var list = self.tasks(in: column.id)
            guard list.contains(where: { ids.contains($0.id) }) else { continue }
            if offset < 0 {
                for i in 1..<max(list.count, 1) where ids.contains(list[i].id) && !ids.contains(list[i - 1].id) {
                    list.swapAt(i, i - 1)
                }
            } else {
                for i in stride(from: list.count - 2, through: 0, by: -1) where ids.contains(list[i].id) && !ids.contains(list[i + 1].id) {
                    list.swapAt(i, i + 1)
                }
            }
            renumber(list)
        }
    }

    /// Sends the selected tasks in each column to that column's top or bottom.
    mutating func moveTasksToEdge(_ ids: Set<String>, top: Bool) {
        for column in columns {
            let inColumn = Set(self.tasks(in: column.id).map(\.id)).intersection(ids)
            if !inColumn.isEmpty { moveTasks(inColumn, to: column.id, placement: top ? .top : .bottom) }
        }
    }
}

/// Drag payload for several tasks: ids separated by newlines (a single id for one task).
enum TaskDrag {
    static func payload(_ ids: [String]) -> String { ids.joined(separator: "\n") }
    static func ids(_ payload: String) -> [String] { payload.split(separator: "\n").map(String.init) }
}
