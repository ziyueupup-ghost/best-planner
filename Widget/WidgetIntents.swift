import AppIntents
import WidgetKit

// Buttons on the desktop widget run these inside the widget process. They edit the
// data file directly; the app notices the file changed and reloads.
//
// Xcode normally generates Metadata.appintents from these types; build.sh writes it
// instead (see make_intents_metadata.py), so keep names and parameters in sync with it.

struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "完成任务"
    static var isDiscoverable: Bool = false

    @Parameter(title: "任务") var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        var board = PlannerStorage.load()
        board.toggleTaskDone(taskID, source: "桌面小组件")
        board.spawnRecurrences()
        PlannerStorage.save(board)
        return .result()
    }
}

struct ToggleSubtaskIntent: AppIntent {
    static var title: LocalizedStringResource = "完成子任务"
    static var isDiscoverable: Bool = false

    @Parameter(title: "任务") var taskID: String
    @Parameter(title: "子任务") var subtaskID: String

    init() {}

    init(taskID: String, subtaskID: String) {
        self.taskID = taskID
        self.subtaskID = subtaskID
    }

    func perform() async throws -> some IntentResult {
        var board = PlannerStorage.load()
        board.toggleSubtask(taskID: taskID, subtaskID: subtaskID, source: "桌面小组件")
        PlannerStorage.save(board)
        return .result()
    }
}
