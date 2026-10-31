// Text is written in Chinese in the code; English comes from this table (like Shared/English.swift).
// "{}" marks a value filled in; "|context" separates identical Chinese words.

const choice = (() => { try { return localStorage.getItem("bp.lang"); } catch { return null; } })();
export const isEnglish = choice ? choice === "en" : !/^zh/i.test(navigator.language || "");

const EN = {
  // Board like the Mac app
  "字体大小": "Text size", "大小": "Size", "按标签筛选": "Filter by tag", "全部标签": "All tags", "管理状态和标签": "Manage statuses and tags",
  "列选项：折叠方式、列宽、清空这一列": "Column options: folding, width, clear", "在「{}」中添加任务": "Add a task to “{}”", "完成列": "Done column",
  "拖动任务到这里": "Drag tasks here", "还有 {} 个日期": "{} more dates", "还有 {} 个附件": "{} more attachments", "🍅 专注 {} 分钟": "🍅 Focused {} min",
  "完成于 {}": "Completed {}", "移到「{}」": "Move to “{}”", "电脑": "Computer", "复制路径": "Copy path", "已复制": "Copied", "复制失败": "Couldn't copy",
  "文件在这台电脑上，要在电脑版 App 里打开。": "The file is on this computer; open it in the Mac app.", "位置": "Location", "打开": "Open",
  "附件和链接（{}）": "Attachments & Links ({})", "特小": "Extra small", "小": "Small", "标准": "Standard", "大": "Large", "特大": "Extra large",
  "超大": "Huge", "巨大": "Giant", "全部展开": "Expand all", "全部折叠": "Collapse all", "恢复默认分组顺序": "Reset group order",
  "清空这一列…": "Clear this column…", "这一列的 {} 个任务会移到「最近删除」，30 天内可以恢复。": "The {} tasks in this column will move to Recently Deleted; you can restore them within 30 days.",
  "列宽": "Column width", "自定义（{}）": "Custom ({})", "自动": "Automatic", "很窄": "Very narrow", "窄": "Narrow", "宽": "Wide", "很宽": "Very wide", "折叠方式": "Folding",
  "切换语言：中文 / English": "Language: 中文 / English",
  "+ 到时移动": "+ Move then", "+ 时间": "+ Time", "7 天内": "Next 7 days", "⏩ 按计划自动移动": "⏩ Moved as planned",
  "「{}」的子任务都已经有了": "All subtasks of “{}” are already there", "「完成」状态里的任务算作已完成。": "Tasks in a “Done” status count as finished.",
  "上移": "Move up", "不折叠": "No folding", "不重复": "Doesn't repeat", "个月": "months", "中": "Normal",
  "从「{}」移到「{}」": "Moved from “{}” to “{}”", "以后": "Later", "优先级": "Priority", "低": "Low", "修改密码": "Change password",
  "全部任务": "All tasks", "出错了，请稍后再试": "Something went wrong, please try again", "创建于「{}」": "Created in “{}”",
  "删除": "Delete", "删除「{}」？": "Delete “{}”?", "删除「{}」？30 天内可以在设置 →「最近删除」里恢复。": "Delete “{}”? You can restore it within 30 days in Settings → Recently Deleted.",
  "删除「{}」？它会从 {} 个任务上移除。": "Delete “{}”? It will be removed from {} tasks.", "删除任务": "Delete task", "删除子任务「{}」": "Deleted subtask “{}”",
  "删除状态「{}」？": "Delete status “{}”?", "删除状态「{}」？里面的 {} 个任务会移到「{}」。": "Delete status “{}”? Its {} tasks will move to “{}”.",
  "删除的任务保留 30 天。": "Deleted tasks are kept for 30 days.", "加这些标签时自动添加：": "Add automatically with these tags:",
  "卡住了": "Struggling", "历史记录（{}）": "History ({})", "去掉日期": "Remove date", "去掉时间": "No time", "同步中…": "Syncing…",
  "名字": "Name", "名称": "Name", "周|repeat": "weeks", "备注": "Notes", "天|repeat": "days", "子任务": "Subtasks", "子任务（{}/{}）": "Subtasks ({}/{})",
  "学习": "Study", "完成": "Done", "完成|history": "Completed", "完成后会自动生成下一次（由电脑版 App 生成）。": "The next one is created when it's done (by the Mac app).",
  "密码": "Password", "密码已修改": "Password changed", "密码至少 8 位": "Password needs at least 8 characters",
  "密码错误次数太多，请 15 分钟后再试": "Too many wrong passwords, try again in 15 minutes", "密码（至少 8 位）": "Password (at least 8 characters)",
  "工作": "Work", "已删除的状态": "a deleted status", "已完成": "Done", "已按标签自动添加 {} 个子任务（{}）": "Added {} subtasks for the tag ({})",
  "已添加「{}」的 {} 个子任务": "Added {1} subtasks from “{0}”", "已登录：": "Signed in: ", "已经有账号？登录": "Have an account? Sign in",
  "已自动保存": "Saved", "已过期": "Overdue", "年|repeat": "years", "应用子任务包…": "Apply subtask pack…", "开始": "Start",
  "当前密码": "Current password", "当前密码不对": "Current password is wrong", "待办": "To do", "恢复": "Restore", "截止": "Deadline",
  "手动排序（拖动调整）": "Manual (drag to arrange)",
  "手机上：用 Safari 打开这个网址，点分享按钮 →「添加到主屏幕」，就能像 App 一样打开。": "On iPhone: open this address in Safari, tap Share → “Add to Home Screen” to use it like an app.",
  "按优先级": "By priority", "按优先级折叠": "Fold by priority", "按创建时间": "By creation", "按日期": "By date", "按日期折叠": "Fold by date",
  "按标签折叠": "Fold by tag", "排在上面的更重要。": "Higher in the list is more important.", "排序": "Sorting", "提醒": "Reminder",
  "搜索任务": "Search tasks", "整列折叠": "Fold whole column", "文件只能在电脑上打开": "Files open on the Mac only",
  "新优先级": "New priority", "新子任务包": "New pack", "新密码至少 8 位": "New password needs at least 8 characters",
  "新密码（至少 8 位）": "New password (at least 8 characters)", "新建任务": "New task", "新标签": "New tag", "新状态": "New status",
  "新联系人": "New contact", "新进展": "New flag", "无标签": "No tag", "日期": "Dates", "更早": "Earlier", "最近 7 天": "Last 7 days",
  "最近删除里没有任务。": "Nothing recently deleted.", "标签": "Tags", "正在载入…": "Loading…", "每 {} {}": "Every {} {}",
  "每两周": "Every 2 weeks", "每个工作日": "Every weekday", "每周": "Weekly", "每天": "Daily", "每年": "Yearly", "每月": "Monthly",
  "每行一个子任务": "One subtask per line", "没有找到匹配的任务": "No matching tasks", "没有日期": "No date", "注册": "Sign up",
  "注册一个账号，手机、电脑和网页都能用。": "Create an account to use it on your phone, computer and the web.", "添加": "Add",
  "添加子任务「{}」": "Added subtask “{}”", "添加日期…": "Add date…", "状态": "Status", "生活": "Life",
  "电脑版 App 在设置 →「云同步」里登录同一个账号，就会和这里自动同步。": "Sign in with the same account in the Mac app (Settings → Cloud Sync) to sync with it.",
  "电话": "Phone", "登录": "Sign in", "登录后，手机、电脑和网页上的任务会自动同步。": "Sign in to sync your tasks across phone, computer and the web.",
  "离线，联网后自动同步": "Offline — will sync when online", "移除": "Remove", "等待中": "Waiting", "紧急": "Urgent",
  "联系人 / 合作人": "Contacts / collaborators", "自定义": "Custom", "至少要保留一个状态。": "Keep at least one status.",
  "要做什么？": "What needs doing?", "设置": "Settings", "说明（可选）": "Note (optional)", "输入名字，回车添加": "Type a name, press Return",
  "输入子任务，回车添加": "Type a subtask, press Return", "输入标题后自动创建": "Created once it has a title", "还没有账号？注册": "No account yet? Sign up",
  "还没有邮箱和电话，可以在设置 →「联系人」里添加。": "No email or phone yet — add them in Settings → Contacts.",
  "这个邮箱已经注册过了": "This email is already registered", "这里还没有任务": "No tasks here yet", "进展": "Progress", "进行中": "Doing",
  "连不上服务器，请检查网络": "Can't reach the server, check your connection", "退出登录": "Sign out", "退出登录？": "Sign out?",
  "邀请码": "Invite code", "还有改动没传到服务器（可能没联网），退出后会丢失。仍然退出？": "Some changes haven't reached the server yet (offline?). Signing out will lose them. Sign out anyway?", "注册成功！": "You're signed up!", "你的账号：": "Your account: ", "立即登录": "Sign in now", "{} 秒后自动跳转到登录页面": "Going to the sign-in page in {} s", "密码不对，还可以再试 {} 次": "Wrong password — {} tries left", "没有这个账号，请检查拼写，或先注册": "No such account — check the spelling, or sign up first", "正在登录…": "Signing in…", "正在注册…": "Signing up…", "账号（邮箱或用户名）": "Account (email or user name)", "账号或密码不对": "Wrong account or password", "这个账号已经被注册了": "This account is already taken", "账号格式不对：用邮箱，或 3–32 位字母、数字、. _ -": "Use an email, or a user name of 3–32 letters, digits, . _ -", "邀请码不对": "Wrong invite code", "邮箱": "Email", "邮箱或密码不对": "Wrong email or password",
  "邮箱格式不对": "That email doesn't look right", "里程碑": "Milestone", "重复": "Repeat", "重新打开": "Reopened", "附件": "Attachments",
  "需要更多信息": "Need more info", "需要跟进": "Follow up", "顺利进行": "On track", "高": "High", "默认": "Default",
  "完成子任务「{}」": "Completed subtask “{}”", "重新打开子任务「{}」": "Reopened subtask “{}”",
  "状态|tab": "Statuses", "标签|tab": "Tags", "优先级|tab": "Priorities", "子任务包": "Subtask packs", "进展|tab": "Progress",
  "联系人": "Contacts", "最近删除": "Recently deleted", "账号": "Account",
};

/** t("删除「{}」？", name) */
export function t(key, ...args) {
  let text = isEnglish && EN[key] !== undefined ? EN[key] : key.replace(/\|.*$/, "");
  if (/\{\d\}/.test(text)) return text.replace(/\{(\d)\}/g, (_, i) => String(args[+i] ?? ""));
  let i = 0;
  return text.replace(/\{\}/g, () => String(args[i++] ?? ""));
}
