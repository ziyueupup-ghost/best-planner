import SwiftUI

/// Edits columns (statuses) and tags. Every change is applied and saved immediately.
///
/// Rows are laid out in a plain ScrollView rather than a List: a List with drag-to-reorder
/// swallows clicks on its text fields on macOS, which made names impossible to edit.
/// Reordering uses ↑/↓ buttons instead.
struct SettingsView: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fontScale) private var fontScale
    @State private var columns: [BoardColumn]
    @State private var tags: [Tag]
    @State private var priorities: [PriorityLevel]
    @State private var defaultPriorityID: String
    @State private var packs: [SubtaskPack]
    @State private var flags: [ProgressFlag]
    @State private var contacts: [Contact]
    @State private var tab = 0
    @State private var expandedTag: String?
    @State private var expandedPack: String?

    init(columns: [BoardColumn], tags: [Tag], priorities: [PriorityLevel], defaultPriorityID: String,
         packs: [SubtaskPack], flags: [ProgressFlag], contacts: [Contact]) {
        _contacts = State(initialValue: contacts)
        _packs = State(initialValue: packs)
        _flags = State(initialValue: flags)
        _columns = State(initialValue: columns)
        _tags = State(initialValue: tags)
        _priorities = State(initialValue: priorities)
        _defaultPriorityID = State(initialValue: defaultPriorityID)
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text(L("状态")).tag(0)
                Text(L("标签")).tag(1)
                Text(L("优先级")).tag(2)
                Text(L("子任务包")).tag(3)
                Text(L("进展")).tag(4)
                Text(L("联系人")).tag(5)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 560)
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 0) {
                    if tab == 0 {
                        ForEach($columns) { $c in
                            columnRow($c)
                                .background(stripe(columns.firstIndex { $0.id == c.id }))
                        }
                    } else if tab == 1 {
                        ForEach($tags) { $t in
                            tagRow($t)
                                .background(stripe(tags.firstIndex { $0.id == t.id }))
                        }
                    } else if tab == 5 {
                        if contacts.isEmpty {
                            Text(L("还没有联系人。在任务的「联系人 / 合作人」里输入名字就会记到这里。"))
                                .foregroundStyle(.secondary)
                                .padding(20)
                        }
                        ForEach($contacts) { $c in
                            contactRow($c)
                                .background(stripe(contacts.firstIndex { $0.id == c.id }))
                        }
                    } else if tab == 4 {
                        ForEach($flags) { $f in
                            flagRow($f)
                                .background(stripe(flags.firstIndex { $0.id == f.id }))
                        }
                    } else if tab == 2 {
                        ForEach($priorities) { $p in
                            priorityRow($p)
                                .background(stripe(priorities.firstIndex { $0.id == p.id }))
                        }
                    } else {
                        if packs.isEmpty {
                            Text(L("还没有子任务包。点下面「添加子任务包」，或在任务里把现有子任务「存为新的子任务包」。"))
                                .foregroundStyle(.secondary)
                                .padding(20)
                        }
                        ForEach($packs) { $pack in
                            packRow($pack)
                                .background(stripe(packs.firstIndex { $0.id == pack.id }))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
            }

            Text(tab == 0
                 ? L("点名称直接修改；左边可以选一个图标。删除状态时，里面的任务会移到第一列。")
                 : tab == 1
                 ? L("点名称直接修改；点「样式」可以设置图案、形状和各部分颜色。删除标签只会把它从任务上移除。")
                 : tab == 5
                 ? L("在任务里用过的联系人都会记在这里，之后在任务里可以直接点选。删除联系人会把他从所有任务上移除。")
                 : tab == 4
                 ? L("给任务标记进展（比如顺利进行、卡住了、需要跟进），会显示在卡片上。在编辑窗口里选，或者右键卡片 →「进展」。删除一个标记，用它的任务会变成没有标记。")
                 : tab == 3
                 ? L("在任务的「子任务」里点「应用子任务包」就能一次加入。加入后是这个任务自己的副本，随便改不影响别的任务。关联了标签的包，给任务加上那个标签时会自动加入。")
                 : L("排在越上面越重要（排序和折叠都按这个顺序）。设了 emoji 的优先级，卡片上显示 emoji，否则显示彩色圆点。删除优先级时，那些任务改成默认优先级。"))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            HStack {
                Button {
                    if tab == 0 {
                        columns.append(BoardColumn(name: L("新状态"), colorHex: Palette.next(after: columns.map(\.colorHex)), icon: "⭐️"))
                    } else if tab == 3 {
                        let pack = SubtaskPack(name: L("新子任务包"), icon: "📦", items: [])
                        packs.append(pack)
                        expandedPack = pack.id
                    } else if tab == 5 {
                        contacts.append(Contact(name: L("新联系人")))
                    } else if tab == 4 {
                        flags.append(ProgressFlag(name: L("新标记"), colorHex: Palette.next(after: flags.map(\.colorHex)), icon: "📍"))
                    } else if tab == 2 {
                        priorities.append(PriorityLevel(name: L("新优先级"), colorHex: Palette.next(after: priorities.map(\.colorHex)), icon: "⭐️"))
                    } else {
                        let tag = Tag(name: L("新标签"), colorHex: Palette.next(after: tags.map(\.colorHex)))
                        tags.append(tag)
                        expandedTag = tag.id
                    }
                } label: {
                    Label([L("添加状态"), L("添加标签"), L("添加优先级"), L("添加子任务包"), L("添加进展标记"), L("添加联系人")][tab], systemImage: "plus")
                }
                Spacer()
                Label(L("已自动保存"), systemImage: "checkmark.circle.fill")
                    .scaledFont(.caption)
                    .foregroundStyle(.green)
                Button(L("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: FontScale.sheetSize(width: 760, height: 640, scale: fontScale).width,
               height: FontScale.sheetSize(width: 760, height: 640, scale: fontScale).height)
        .onChange(of: columns) { _, _ in apply() }
        .onChange(of: tags) { _, _ in apply() }
        .onChange(of: priorities) { _, _ in apply() }
        .onChange(of: defaultPriorityID) { _, _ in apply() }
        .onChange(of: packs) { _, _ in apply() }
        .onChange(of: flags) { _, _ in apply() }
        .onChange(of: contacts) { _, _ in apply() }
        .onExitCommand { dismiss() }
    }

    // MARK: Status rows

    private func columnRow(_ c: Binding<BoardColumn>) -> some View {
        let id = c.wrappedValue.id
        let i = columns.firstIndex { $0.id == id } ?? 0
        return HStack(spacing: 10) {
            ReorderButtons(index: i, count: columns.count) { columns.swapAt(i, $0) }
            IconPicker(icon: c.icon)
            ColorSwatchPicker(hex: c.colorHex)
            TextField(L("名称"), text: c.name)
                .textFieldStyle(.roundedBorder)
            Toggle(L("完成列"), isOn: c.isDone)
                .toggleStyle(.checkbox)
                .help(L("这一列的任务算作已完成，会记录完成日期"))
            Text(L("\(store.tasks.filter { $0.columnID == id }.count) 项"))
                .scaledFont(.caption, monospacedDigit: true)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Button {
                columns.removeAll { $0.id == id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(columns.count <= 1)
            .help(L("删除状态（里面的任务会移到第一列）"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Tag rows

    private func tagRow(_ binding: Binding<Tag>) -> some View {
        let t = binding.wrappedValue
        let i = tags.firstIndex { $0.id == t.id } ?? 0
        let expanded = expandedTag == t.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ReorderButtons(index: i, count: tags.count) { tags.swapAt(i, $0) }
                TagChip(tag: t)
                    .frame(width: 120, alignment: .leading)
                TextField(L("名称"), text: binding.name)
                    .textFieldStyle(.roundedBorder)
                Text(L("\(store.tasks.filter { $0.tagIDs.contains(t.id) }.count) 项"))
                    .scaledFont(.caption, monospacedDigit: true)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Button {
                    withAnimation(.snappy) { expandedTag = expanded ? nil : t.id }
                } label: {
                    Label(expanded ? L("收起") : L("样式"), systemImage: expanded ? "chevron.up" : "paintpalette")
                }
                Button {
                    if expanded { expandedTag = nil }
                    tags.removeAll { $0.id == t.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L("删除标签"))
            }
            if expanded {
                TagStyleEditor(tag: binding)
                    .padding(.leading, 44)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Priority rows

    private func priorityRow(_ p: Binding<PriorityLevel>) -> some View {
        let id = p.wrappedValue.id
        let i = priorities.firstIndex { $0.id == id } ?? 0
        let isDefault = defaultPriorityID == id
        return HStack(spacing: 10) {
            ReorderButtons(index: i, count: priorities.count) { priorities.swapAt(i, $0) }
            IconPicker(icon: p.icon)
            ColorSwatchPicker(hex: p.colorHex)
            TextField(L("名称"), text: p.name)
                .textFieldStyle(.roundedBorder)
            PriorityMark(level: p.wrappedValue)
                .frame(width: 24)
            Button {
                defaultPriorityID = id
            } label: {
                Label(L("默认"), systemImage: isDefault ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isDefault ? Color.accentColor : .secondary)
            .help(L("新建任务时默认用这个优先级"))
            Text(L("\(store.tasks.filter { store.board.priority(of: $0).id == id }.count) 项"))
                .scaledFont(.caption, monospacedDigit: true)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Button {
                priorities.removeAll { $0.id == id }
                if isDefault, let first = priorities.first { defaultPriorityID = first.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(priorities.count <= 1)
            .help(L("删除优先级（这些任务改成默认优先级）"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Progress flag rows

    private func flagRow(_ f: Binding<ProgressFlag>) -> some View {
        let id = f.wrappedValue.id
        let i = flags.firstIndex { $0.id == id } ?? 0
        return HStack(spacing: 10) {
            ReorderButtons(index: i, count: flags.count) { flags.swapAt(i, $0) }
            IconPicker(icon: f.icon)
            ColorSwatchPicker(hex: f.colorHex)
            TextField(L("名称"), text: f.name)
                .textFieldStyle(.roundedBorder)
            FlagChip(flag: f.wrappedValue)
            Text(L("\(store.tasks.filter { $0.flagIDs.contains(id) }.count) 项"))
                .scaledFont(.caption, monospacedDigit: true)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Button {
                flags.removeAll { $0.id == id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L("删除这个进展标记（用它的任务会变成没有标记）"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Contact rows

    private func contactRow(_ c: Binding<Contact>) -> some View {
        let id = c.wrappedValue.id
        return HStack(spacing: 10) {
            Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
            TextField(L("名字"), text: c.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            TextField(L("邮箱"), text: c.email)
                .textFieldStyle(.roundedBorder)
            TextField(L("电话"), text: c.phone)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Text(L("\(store.tasks.filter { $0.contactIDs.contains(id) }.count) 项"))
                .scaledFont(.caption, monospacedDigit: true)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Button {
                contacts.removeAll { $0.id == id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L("删除这个联系人（会从所有任务上移除）"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Subtask pack rows

    private func packRow(_ binding: Binding<SubtaskPack>) -> some View {
        let pack = binding.wrappedValue
        let i = packs.firstIndex { $0.id == pack.id } ?? 0
        let expanded = expandedPack == pack.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ReorderButtons(index: i, count: packs.count) { packs.swapAt(i, $0) }
                IconPicker(icon: binding.icon)
                TextField(L("名称"), text: binding.name)
                    .textFieldStyle(.roundedBorder)
                Text(L("\(pack.items.count) 项"))
                    .scaledFont(.caption, monospacedDigit: true)
                    .foregroundStyle(.secondary)
                ForEach(tags.filter { pack.autoTagIDs.contains($0.id) }) { TagChip(tag: $0, small: true) }
                Button {
                    withAnimation(.snappy) { expandedPack = expanded ? nil : pack.id }
                } label: {
                    Label(expanded ? L("收起") : L("编辑"), systemImage: expanded ? "chevron.up" : "list.bullet")
                }
                Button {
                    if expanded { expandedPack = nil }
                    packs.removeAll { $0.id == pack.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L("删除子任务包（已经加到任务里的子任务不受影响）"))
            }
            if expanded {
                PackEditor(pack: binding, tags: tags)
                    .padding(.leading, 44)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Helpers

    private func stripe(_ index: Int?) -> Color {
        (index ?? 0).isMultiple(of: 2) ? Color.primary.opacity(0.04) : .clear
    }


    /// Pushes the edited lists to the store. Blank names are saved as 未命名 so a tag
    /// is never dropped (and removed from tasks) just because its name is being retyped.
    private func apply() {
        let cols = columns.map { c in
            var c = c
            c.name = c.name.trimmingCharacters(in: .whitespaces)
            if c.name.isEmpty { c.name = L("未命名") }
            return c
        }
        let tgs = tags.map { t in
            var t = t
            t.name = t.name.trimmingCharacters(in: .whitespaces)
            if t.name.isEmpty { t.name = L("未命名") }
            return t
        }
        let prs = priorities.map { p in
            var p = p
            p.name = p.name.trimmingCharacters(in: .whitespaces)
            if p.name.isEmpty { p.name = L("未命名") }
            return p
        }
        let pks = packs.map { p in
            var p = p
            p.name = p.name.trimmingCharacters(in: .whitespaces)
            if p.name.isEmpty { p.name = L("未命名") }
            return p
        }
        let fls = flags.map { f in
            var f = f
            f.name = f.name.trimmingCharacters(in: .whitespaces)
            if f.name.isEmpty { f.name = L("未命名") }
            return f
        }
        store.applySettings(columns: cols, tags: tgs, priorities: prs, defaultPriorityID: defaultPriorityID, packs: pks, flags: fls, contacts: contacts.map { c in
            var c = c
            c.name = c.name.trimmingCharacters(in: .whitespaces)
            if c.name.isEmpty { c.name = L("未命名") }
            return c
        })
    }
}

/// Looks, color combos, emoji, shape, style, border and per-part colors for one tag.
private struct TagStyleEditor: View {
    @Binding var tag: Tag

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                label(L("一键风格"))
                FlowLayout(spacing: 6) {
                    ForEach(TagLook.all) { look in
                        let preview = { var p = tag; look.apply(to: &p); p.name = look.name; return p }()
                        choice(false, help: L("套用「\(look.name)」")) { look.apply(to: &tag) } content: {
                            TagChip(tag: preview)
                        }
                    }
                }
            }
            GridRow {
                label(L("颜色搭配"))
                FlowLayout(spacing: 6) {
                    ForEach(TagColorPreset.all) { preset in
                        let preview = { var p = tag; preset.apply(to: &p); p.name = preset.name; return p }()
                        choice(preset.color == tag.colorHex && preset.fill == tag.fillHex && preset.text == tag.textHex,
                               help: L("套用「\(preset.name)」配色")) { preset.apply(to: &tag) } content: {
                            TagChip(tag: preview)
                        }
                    }
                }
            }
            GridRow {
                label(L("图案"))
                IconPicker(icon: $tag.icon)
            }
            GridRow {
                label(L("形状"))
                FlowLayout(spacing: 6) {
                    ForEach(TagShape.allCases) { shape in
                        let preview = { var p = tag; p.shape = shape; p.name = shape.title; return p }()
                        choice(tag.shape == shape, help: shape.title) { tag.shape = shape } content: {
                            TagChip(tag: preview)
                        }
                    }
                }
            }
            GridRow {
                label(L("样式"))
                FlowLayout(spacing: 6) {
                    ForEach(TagStyle.allCases) { style in
                        let preview = { var p = tag; p.style = style; p.name = style.title; return p }()
                        choice(tag.style == style, help: style.title) { tag.style = style } content: {
                            TagChip(tag: preview)
                        }
                    }
                }
            }
            GridRow {
                label(L("边框线条"))
                FlowLayout(spacing: 6) {
                    ForEach(TagBorder.allCases) { border in
                        let preview = { var p = tag; p.border = border; p.name = border.title; return p }()
                        choice(tag.border == border, help: border.title) { tag.border = border } content: {
                            TagChip(tag: preview)
                        }
                    }
                }
            }
            GridRow {
                label(L("线条粗细"))
                Picker("", selection: $tag.borderWidth) {
                    ForEach(TagBorderWidth.options, id: \.value) { Text($0.title).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }
            GridRow {
                label(L("主色"))
                ColorSwatchPicker(hex: $tag.colorHex)
            }
            GridRow {
                label(L("文字颜色"))
                OptionalColorControl(hex: $tag.textHex, automatic: tag.defaultTextColor)
            }
            GridRow {
                label(L("背景颜色"))
                OptionalColorControl(hex: $tag.fillHex, automatic: tag.defaultFillColor, palette: Palette.pastel + Palette.colors)
            }
            GridRow {
                label(L("边框颜色"))
                OptionalColorControl(hex: $tag.borderHex, automatic: tag.defaultBorderColor)
            }
        }
        .scaledFont(.callout)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 60, alignment: .trailing)
            .padding(.top, 4)
    }

    private func choice<Content: View>(_ selected: Bool, help: String, action: @escaping () -> Void,
                                       @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// "自动" (derived from the tag's main color and style) or a custom color.
private struct OptionalColorControl: View {
    @Binding var hex: String?
    let automatic: Color?
    var palette: [String] = Palette.colors

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { hex != nil },
                set: { custom in hex = custom ? (automatic ?? .gray).hexString : nil }
            )) {
                Text(L("自动")).tag(false)
                Text(L("自定义")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            if hex != nil {
                ColorSwatchPicker(hex: Binding(get: { hex ?? "#888888" }, set: { hex = $0 }), palette: palette)
            } else {
                Text(automatic == nil ? L("无") : L("跟随主色和样式"))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Items of a subtask pack and the tags that add it automatically.
private struct PackEditor: View {
    @Binding var pack: SubtaskPack
    let tags: [Tag]
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("子任务")).scaledFont(.callout).foregroundStyle(.secondary)
            ForEach(Array(pack.items.indices), id: \.self) { i in
                HStack(spacing: 8) {
                    ReorderButtons(index: i, count: pack.items.count) { pack.items.swapAt(i, $0) }
                    Image(systemName: "square").foregroundStyle(.tertiary)
                    TextField(L("子任务"), text: Binding(
                        get: { i < pack.items.count ? pack.items[i] : "" },
                        set: { if i < pack.items.count { pack.items[i] = $0 } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button {
                        if i < pack.items.count { pack.items.remove(at: i) }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 18)
                TextField(L("新子任务"), text: $newItem, prompt: Text(L("输入子任务，回车添加")))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(L("添加"), action: add)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text(L("给任务加上这些标签时，自动加入这个包："))
                .scaledFont(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            if tags.isEmpty {
                Text(L("还没有标签")).scaledFont(.caption).foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        let on = pack.autoTagIDs.contains(tag.id)
                        Button {
                            if on { pack.autoTagIDs.removeAll { $0 == tag.id } } else { pack.autoTagIDs.append(tag.id) }
                        } label: {
                            TagChip(tag: tag, selected: on)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func add() {
        let item = newItem.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        pack.items.append(item)
        newItem = ""
    }
}

private struct ReorderButtons: View {
    let index: Int
    let count: Int
    let swap: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button { swap(index - 1) } label: { Image(systemName: "chevron.up").scaledFont(.caption2, weight: .bold) }
                .disabled(index == 0)
                .help(L("上移"))
            Button { swap(index + 1) } label: { Image(systemName: "chevron.down").scaledFont(.caption2, weight: .bold) }
                .disabled(index >= count - 1)
                .help(L("下移"))
        }
        .buttonStyle(.borderless)
        .frame(width: 18)
    }
}

/// One emoji: type any (⌃⌘Space opens the system emoji panel) or pick a preset.
struct IconPicker: View {
    @Binding var icon: String
    @State private var showPresets = false

    static let presets = [
        "📝", "📌", "⭐️", "🔥", "🏃", "⏳", "🚀", "✅", "🎉", "🏆",
        "💡", "🎯", "📚", "💼", "🏠", "🌱", "☕️", "🧪", "📅", "⚠️",
        "❤️", "💰", "✈️", "🎨", "🎵", "💪", "🐎", "🍀", "💤", "🔒",
    ]

    var body: some View {
        Button {
            showPresets = true
        } label: {
            Text(icon.isEmpty ? "＋" : icon)
                .scaledFont(.title3)
                .frame(width: 30, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(L("选择图标"))
        .popover(isPresented: $showPresets, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
                    ForEach(Self.presets, id: \.self) { emoji in
                        Button {
                            icon = emoji
                            showPresets = false
                        } label: {
                            Text(emoji)
                                .scaledFont(.title3)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6).fill(icon == emoji ? Color.accentColor.opacity(0.25) : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField(L("自己输入"), text: Binding(
                        get: { icon },
                        set: { icon = $0.last.map(String.init) ?? "" }
                    ), prompt: Text(L("或输入任意 emoji")))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    Text(L("⌃⌘空格 打开表情面板"))
                        .scaledFont(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("不要图标")) {
                        icon = ""
                        showPresets = false
                    }
                }
            }
            .padding(12)
        }
    }
}
