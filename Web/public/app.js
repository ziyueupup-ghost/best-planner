// Best Planner on the web: the same board as the Mac app, synced through the server.
import { mergeBoards, same } from "./merge.js";
import { t, isEnglish } from "./i18n.js";
import { tagChipHTML, drawTagShapes, rgba } from "./tags.js";

// MARK: - State and sync

const store = {
  token: load("bp.token"),
  email: load("bp.email"),
  board: null,     // what's shown and edited
  base: null,      // the server's board as of `version` (base for merging)
  version: 0,
  dirty: false,
  saving: false,
  online: true,
};

function load(key) { try { return localStorage.getItem(key); } catch { return null; } }
function save(key, value) { try { value == null ? localStorage.removeItem(key) : localStorage.setItem(key, value); } catch {} }

function cacheBoard() {
  try {
    localStorage.setItem("bp.cache", JSON.stringify({ email: store.email, board: store.board, base: store.base, version: store.version, dirty: store.dirty }));
  } catch {}
}

function restoreCache() {
  try {
    const c = JSON.parse(localStorage.getItem("bp.cache") || "null");
    if (c && c.email === store.email && c.board) Object.assign(store, { board: c.board, base: c.base, version: c.version, dirty: c.dirty });
  } catch {}
}

async function api(method, path, data) {
  // Give up after 20 seconds instead of spinning for minutes on a bad connection.
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 20_000);
  const res = await fetch(path, {
    method,
    signal: abort.signal,
    headers: { "Content-Type": "application/json", ...(store.token ? { Authorization: `Bearer ${store.token}` } : {}) },
    body: data === undefined ? undefined : JSON.stringify(data),
  }).finally(() => clearTimeout(timer));
  const body = await res.json().catch(() => ({}));
  // Only an expired or unknown session signs out (not, say, a wrong password).
  if (res.status === 401 && body.error === "auth") { signOut(); throw new Error("auth"); }
  return { status: res.status, body };
}

/** Pull the server's board; merge it with local edits; push if anything is left to send. */
let syncing = null;
async function sync() {
  if (!store.token) return;
  if (syncing) { syncAgain = true; return syncing; }
  syncing = (async () => {
    try {
      // Without a board yet (just signed in), always ask for the whole thing.
      const { status, body } = await api("GET", store.board ? `/api/board?known=${store.version}` : "/api/board");
      if (status !== 200) throw new Error(body.error || status);
      if (!body.unchanged) absorb(body.version, body.board);
      for (let attempt = 0; attempt < 5 && store.dirty; attempt++) {
        const sent = snapshot(store.board);
        const r = await api("PUT", "/api/board", { baseVersion: store.version, board: sent });
        if (r.status === 200) {
          store.version = r.body.version;
          store.base = sent;
          store.dirty = !same(store.board, sent);   // edited again while sending
        } else if (r.status === 409) {
          absorb(r.body.version, r.body.board);
        } else {
          throw new Error(r.body.error || r.status);
        }
      }
      setOnline(true);
    } catch (e) {
      if (e.message !== "auth") setOnline(false);
    } finally {
      cacheBoard();
      renderStatus();
      syncing = null;
      if (syncAgain) { syncAgain = false; scheduleSync(300); }
    }
  })();
  return syncing;
}
let syncAgain = false;

/** A separate copy, so later edits to the board can't change the synced snapshot (base). */
const snapshot = (board) => JSON.parse(JSON.stringify(board));

/** A newer board from the server. */
function absorb(version, theirs) {
  if (!theirs) {
    // Nothing on the server yet (new account): start a board and upload it.
    store.version = version;
    if (!store.board) { store.board = emptyBoard(); store.dirty = true; }
    else store.dirty = true;
    store.base = null;
    render();
    return;
  }
  normalize(theirs);
  let next;
  if (!store.board || !store.dirty) next = theirs;
  else if (store.base) next = mergeBoards(store.base, store.board, theirs);
  else next = mergeBoards({ ...theirs, tasks: [], trash: [], contacts: [] }, store.board, theirs);
  store.version = version;
  store.base = snapshot(theirs);
  store.dirty = !same(next, theirs);
  store.board = next;
  if (applyDueMoves()) store.dirty = true;   // moves that came due must be sent too
  render();
}

let syncTimer = null;
function scheduleSync(ms = 800) {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(sync, ms);
}

/** Every edit goes through here: saves locally at once and to the server shortly after. */
function changed() {
  store.dirty = true;
  cacheBoard();
  render();
  scheduleSync();
}

function setOnline(on) {
  if (store.online === on) return;
  store.online = on;
  renderStatus();
}

setInterval(() => { if (document.visibilityState === "visible") sync(); }, 10_000);
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") sync(); else if (store.dirty) sync(); });
setInterval(() => { if (store.board && applyDueMoves()) changed(); }, 30_000);

// MARK: - Board helpers

const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`).toUpperCase();
const nowISO = () => iso(new Date());
const iso = (d) => d.toISOString().replace(/\.\d{3}Z$/, "Z");

function emptyBoard() {
  return {
    columns: [
      { id: "todo", name: t("待办"), colorHex: "#5B85F5", icon: "📝", isDone: false, foldMode: "off", groupOrder: [] },
      { id: "doing", name: t("进行中"), colorHex: "#F79E33", icon: "🏃", isDone: false, foldMode: "off", groupOrder: [] },
      { id: "done", name: t("已完成"), colorHex: "#40B873", icon: "🎉", isDone: true, foldMode: "off", groupOrder: [] },
    ],
    tags: [
      { id: uuid(), name: t("工作"), colorHex: "#5B85F5", icon: "💼" },
      { id: uuid(), name: t("学习"), colorHex: "#9B6CF0", icon: "📚" },
      { id: uuid(), name: t("生活"), colorHex: "#40B873", icon: "🌱" },
    ],
    tasks: [], trash: [], sortMode: "manual", expandedGroups: [],
    priorities: [
      { id: "urgent", name: t("紧急"), colorHex: "#E5534B", icon: "🔥" },
      { id: "high", name: t("高"), colorHex: "#F79E33", icon: "⬆️" },
      { id: "normal", name: t("中"), colorHex: "#5B85F5", icon: "" },
      { id: "low", name: t("低"), colorHex: "#8D99AE", icon: "⬇️" },
    ],
    defaultPriorityID: "normal",
    subtaskPacks: [],
    dayNotes: {},
    flags: [
      { id: "on-track", name: t("顺利进行"), colorHex: "#40B873", icon: "🟢" },
      { id: "struggling", name: t("卡住了"), colorHex: "#E5534B", icon: "😣" },
      { id: "follow-up", name: t("需要跟进"), colorHex: "#F79E33", icon: "🔁" },
      { id: "need-info", name: t("需要更多信息"), colorHex: "#9B6CF0", icon: "❓" },
      { id: "waiting", name: t("等待中"), colorHex: "#8D99AE", icon: "⏳" },
    ],
    contacts: [], widgetColumnIDs: [], widgetTagIDs: [],
  };
}

/** Fill in fields older boards may lack, so the rest of the code can rely on them. */
function normalize(b) {
  for (const k of ["columns", "tags", "tasks", "trash", "priorities", "subtaskPacks", "flags", "contacts", "expandedGroups"]) b[k] ||= [];
  b.dayNotes ||= {};
  for (const task of [...b.tasks, ...b.trash]) {
    for (const k of ["tagIDs", "dates", "subtasks", "history", "links", "flagIDs", "contactIDs", "autoMoves", "focusSessions"]) task[k] ||= [];
  }
  return b;
}

const B = () => store.board;
const column = (id) => B().columns.find((c) => c.id === id);
const tag = (id) => B().tags.find((x) => x.id === id);
const contact = (id) => B().contacts.find((x) => x.id === id);
const taskByID = (id) => B().tasks.find((x) => x.id === id);
const isDone = (task) => !!column(task.columnID)?.isDone;
const priorityOf = (task) => B().priorities.find((p) => p.id === task.priorityID)
  || B().priorities.find((p) => p.id === B().defaultPriorityID) || B().priorities[0] || { id: "normal", name: t("中"), colorHex: "#5B85F5", icon: "" };
const label = (x) => (x.icon ? `${x.icon} ${x.name}` : x.name);

function tasksIn(columnID, list = B().tasks) {
  const done = column(columnID)?.isDone;
  const rank = (task) => { const i = B().priorities.findIndex((p) => p.id === priorityOf(task).id); return i < 0 ? 99 : i; };
  const next = (task) => nextDate(task)?.date || null;
  const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
  const items = list.filter((x) => x.columnID === columnID);
  switch (B().sortMode) {
    case "priority": if (!done) return items.sort((a, b) => rank(a) - rank(b) || cmpDates(next(a), next(b)) || cmp(b.updatedAt, a.updatedAt));
    // falls through for done columns
    case "date": if (!done) return items.sort((a, b) => cmpDates(next(a), next(b)) || rank(a) - rank(b));
    case "created": if (!done) return items.sort((a, b) => cmp(b.createdAt, a.createdAt));
      return items.sort((a, b) => cmp(b.completedAt || b.updatedAt, a.completedAt || a.updatedAt));
    default: return items.sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || cmp(b.updatedAt, a.updatedAt));
  }
}
const cmpDates = (x, y) => (x && y ? (x < y ? -1 : x > y ? 1 : 0) : x ? -1 : y ? 1 : 0);

function nextDate(task) {
  const sorted = [...task.dates].sort((a, b) => cmpDates(a.date, b.date));
  const today = startOfDay(new Date());
  return sorted.find((d) => new Date(d.date) >= today) || sorted[sorted.length - 1];
}

const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const showsTime = (d) => d.kind === "reminder" || d.hasTime;
const dueOf = (d) => (showsTime(d) ? new Date(d.date) : startOfDay(new Date(d.date)));

/** Like the Mac: the system's own short date format ("12/11 下午1:00", "15/11/26"). */
function dateLabel(isoString, withTime, withYear = false) {
  const d = new Date(isoString);
  const opts = withTime ? { month: "numeric", day: "numeric", hour: "numeric", minute: "2-digit" }
    : { month: "numeric", day: "numeric", ...(withYear ? { year: "2-digit" } : {}) };
  try { return d.toLocaleString(undefined, opts); } catch { return d.toLocaleDateString(); }
}

function isOverdue(d, task) {
  if (d.kind !== "deadline" || isDone(task)) return false;
  return d.hasTime ? new Date(d.date) < new Date() : new Date(d.date) < startOfDay(new Date());
}

const subOverdue = (s) => s.date && !s.isDone && (s.hasTime ? new Date(s.date) < new Date() : new Date(s.date) < startOfDay(new Date()));

function addHistory(task, kind, text) {
  task.history.push({ id: uuid(), date: nowISO(), kind, text });
}

/** Moving to another status: completion date and history like on the Mac. */
function moveTask(task, columnID, auto = false) {
  if (task.columnID === columnID) return;
  const from = column(task.columnID), to = column(columnID);
  const wasDone = !!from?.isDone;
  task.columnID = columnID;
  task.order = topOrder(columnID) ;
  if (auto) addHistory(task, "moved", t("⏩ 按计划自动移动"));
  else if (to?.isDone && !wasDone) addHistory(task, "completed", t("完成|history"));
  else if (wasDone && !to?.isDone) addHistory(task, "reopened", t("重新打开"));
  else addHistory(task, "moved", t("从「{}」移到「{}」", from?.name || t("已删除的状态"), to?.name || ""));
  if (to?.isDone && !wasDone) task.completedAt = nowISO();
  if (!to?.isDone) delete task.completedAt;
  task.updatedAt = nowISO();
}

function topOrder(columnID) {
  const orders = B().tasks.filter((x) => x.columnID === columnID).map((x) => x.order ?? 0);
  return orders.length ? Math.min(...orders) - 1 : 0;
}

/** Dates with "到时移到" (and older planned moves) that are due: move the task. */
function applyDueMoves() {
  let moved = false;
  const now = new Date();
  for (const task of B().tasks) {
    const due = [
      ...task.dates.filter((d) => d.moveTo && dueOf(d) <= now).map((d) => ({ at: dueOf(d), to: d.moveTo, clear: () => { delete d.moveTo; } })),
      ...task.autoMoves.filter((m) => (m.hasTime === false ? startOfDay(new Date(m.date)) : new Date(m.date)) <= now)
        .map((m) => ({ at: new Date(m.date), to: m.columnID, clear: () => { task.autoMoves = task.autoMoves.filter((x) => x.id !== m.id); } })),
    ].sort((a, b) => a.at - b.at);
    if (!due.length) continue;
    for (const d of due) d.clear();
    const target = due[due.length - 1].to;
    if (column(target) && target !== task.columnID) moveTask(task, target, true);
    else task.updatedAt = nowISO();
    moved = true;
  }
  return moved;
}

// MARK: - Rendering

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const app = $("#app");

const ui = {
  columnID: load("bp.column"),
  search: "",
  tagFilter: load("bp.tagFilter"),
  editing: null,     // task id
  openSubtasks: new Set(),
  settingsTab: null,
};

function render() {
  if (!store.token) return renderSignIn();
  if (!store.board) { app.innerHTML = `<div class="loading">${t("正在载入…")}</div>`; return; }
  if (!$(".board-shell")) {
    app.innerHTML = `
      <header class="topbar">
        <h1>Best Planner</h1>
        <span class="status" id="status"></span>
        <div class="tools" id="tools"></div>
        <label class="search"><span class="search-icon">${icon("search")}</span><input id="search" type="search" placeholder="${t("搜索任务")}" value="${esc(ui.search)}"></label>
        <nav class="tabs" id="tabs"></nav>
      </header>
      <main class="board-shell" id="board"></main>
      <div id="modal"></div>`;
    $("#search").addEventListener("input", (e) => { ui.search = e.target.value; renderBoard(); });
  }
  renderStatus();
  renderTools();
  renderBoard();
  if (ui.editing) renderEditor();
  if (ui.settingsTab) renderSettings();
}

function renderStatus() {
  const el = $("#status");
  if (!el) return;
  el.textContent = store.online ? (store.dirty ? t("同步中…") : "") : t("离线，联网后自动同步");
  el.className = `status ${store.online ? "" : "offline"}`;
}

function filtered() {
  const q = ui.search.trim().toLowerCase();
  if (ui.tagFilter && !tag(ui.tagFilter)) ui.tagFilter = null;
  const tasks = ui.tagFilter ? B().tasks.filter((x) => x.tagIDs.includes(ui.tagFilter)) : B().tasks;
  if (!q) return tasks;
  return tasks.filter((x) => x.title.toLowerCase().includes(q) || (x.notes || "").toLowerCase().includes(q)
    || x.subtasks.some((s) => s.title.toLowerCase().includes(q))
    || x.tagIDs.some((id) => (tag(id)?.name || "").toLowerCase().includes(q)));
}

function currentColumn() {
  return column(ui.columnID) || B().columns[0];
}

function renderTools() {
  const el = $("#tools");
  if (!el) return;
  const filterTag = ui.tagFilter && tag(ui.tagFilter);
  el.innerHTML = `
    <div class="tool-group">
      <button class="tool" data-act="menu" data-menu="lang" title="${t("切换语言：中文 / English")}">${icon("globe")}<span class="caret">⌄</span></button>
    </div>
    <div class="tool-group">
      <button class="tool text" data-act="menu" data-menu="size" title="${t("字体大小")}">${t("大小")}<span class="caret">⌄</span></button>
      <button class="tool" data-act="menu" data-menu="sort" title="${t("排序")}">${icon("sort")}<span class="caret">⌄</span></button>
      <button class="tool ${filterTag ? "on" : ""}" data-act="menu" data-menu="tags" title="${t("按标签筛选")}">${icon("tag")}${filterTag ? `<span class="tool-label">${esc(filterTag.name)}</span>` : ""}<span class="caret">⌄</span></button>
    </div>
    <div class="tool-group">
      <button class="tool" data-act="settings" title="${t("管理状态和标签")}">${icon("sliders")}</button>
      <button class="tool" data-act="trash" title="${t("最近删除")}">${icon("trash")}</button>
      <button class="tool" data-act="new" title="${t("新建任务")}">${icon("plus")}</button>
    </div>`;
}

function renderBoard() {
  const list = filtered();
  const current = currentColumn();
  $("#tabs").innerHTML = B().columns.map((c) => `
    <button class="tab ${c.id === current.id ? "on" : ""}" data-act="tab" data-id="${esc(c.id)}" style="--c:${esc(c.colorHex)}">
      ${c.icon ? `<span>${esc(c.icon)}</span>` : ""}<b>${esc(c.name)}</b><span class="count">${tasksIn(c.id, list).length}</span>
    </button>`).join("");
  $("#board").innerHTML = B().columns.map((c) => `
    <section class="column ${c.id === current.id ? "current" : ""}" data-column="${esc(c.id)}" style="--c:${esc(c.colorHex)};${c.width ? `--w:${c.width}px` : ""}">
      <div class="column-head">
        ${c.icon ? `<span class="col-icon">${esc(c.icon)}</span>` : `<span class="col-dot"></span>`}<b class="col-name">${esc(c.name)}</b>
        ${c.isDone ? `<span class="col-done" title="${t("完成列")}">${icon("seal")}</span>` : ""}
        <span class="col-count">${tasksIn(c.id, list).length}</span>
        <span class="spacer"></span>
        <button class="col-btn ${c.foldMode && c.foldMode !== "off" ? "active" : ""}" data-act="menu" data-menu="fold" data-column="${esc(c.id)}" title="${t("列选项：折叠方式、列宽、清空这一列")}">${icon(FOLD_ICONS[c.foldMode || "off"] || "compress")}</button>
        <button class="col-btn" data-act="new" data-column="${esc(c.id)}" title="${t("在「{}」中添加任务", c.name)}">${icon("plus")}</button>
      </div>
      <div class="cards">${renderColumnTasks(c, tasksIn(c.id, list))}</div>
    </section>`).join("");
  drawTagShapes($("#board"));
}

const FOLD_ICONS = { off: "compress", all: "compress", tag: "tag", priority: "alert", date: "calendar" };

function renderColumnTasks(c, tasks) {
  if (!tasks.length) return `<p class="empty">${ui.search || ui.tagFilter ? t("没有找到匹配的任务") : t("拖动任务到这里")}</p>`;
  if (!c.foldMode || c.foldMode === "off") return tasks.map(card).join("");
  return foldGroups(c, tasks).map((g) => {
    const open = !!ui.search || B().expandedGroups.includes(`${c.id}|${g.key}`);
    return `<div class="group">
      <button class="group-head" data-act="group" data-column="${esc(c.id)}" data-key="${esc(g.key)}">
        <span class="chev ${open ? "open" : ""}">${icon("chevR")}</span>${g.header}<span class="group-count">${g.tasks.length}</span>
      </button>
      ${open ? g.tasks.map(card).join("") : ""}
    </div>`;
  }).join("");
}

function foldGroups(c, tasks) {
  let groups = [];
  if (c.foldMode === "all") groups = [{ key: "all", header: `<b>${t("全部任务")}</b>`, tasks }];
  else if (c.foldMode === "tag") {
    groups = B().tags.map((g) => ({ key: `tag-${g.id}`, header: tagChipHTML(g), tasks: tasks.filter((x) => x.tagIDs.find((id) => tag(id)) === g.id) }));
    groups.push({ key: "tag-none", header: `<b class="muted">${t("无标签")}</b>`, tasks: tasks.filter((x) => !x.tagIDs.some((id) => tag(id))) });
  } else if (c.foldMode === "priority") {
    groups = B().priorities.map((p) => ({ key: `priority-${p.id}`, header: `<b style="color:${esc(p.colorHex)}">${esc(label(p))}</b>`, tasks: tasks.filter((x) => priorityOf(x).id === p.id) }));
  } else {
    // By date: this week / later / no date (a simpler version of the Mac's buckets).
    const today = startOfDay(new Date()), week = new Date(today.getTime() + 7 * 86_400_000);
    const when = (x) => (c.isDone ? x.completedAt : nextDate(x)?.date);
    groups = [
      { key: "date-soon", header: `<b>${c.isDone ? t("最近 7 天") : t("7 天内")}</b>`, tasks: tasks.filter((x) => when(x) && (c.isDone ? new Date(when(x)) >= new Date(today - 7 * 86_400_000) : new Date(when(x)) < week)) },
      { key: "date-later", header: `<b>${c.isDone ? t("更早") : t("以后")}</b>`, tasks: tasks.filter((x) => when(x) && !(c.isDone ? new Date(when(x)) >= new Date(today - 7 * 86_400_000) : new Date(when(x)) < week)) },
      { key: "date-none", header: `<b class="muted">${t("没有日期")}</b>`, tasks: tasks.filter((x) => !when(x)) },
    ];
  }
  groups = groups.filter((g) => g.tasks.length);
  const order = c.groupOrder || [];
  if (order.length) groups.sort((a, b) => ((order.indexOf(a.key) + 1 || 1e9) - (order.indexOf(b.key) + 1 || 1e9)));
  return groups;
}

function tagChip(g, extra = "") {
  return tagChipHTML(g, { off: extra === "off" });
}

function flagChip(f, extra = "") {
  return `<span class="chip flag ${extra}" style="--c:${esc(f.colorHex)}">${f.icon ? `<span>${esc(f.icon)}</span>` : ""}<b>${esc(f.name)}</b></span>`;
}

function card(task) {
  const done = isDone(task);
  const p = priorityOf(task);
  const accent = task.colorHex || column(task.columnID)?.colorHex || "#888";
  const tags = task.tagIDs.map(tag).filter(Boolean);
  const flags = B().flags.filter((f) => task.flagIDs.includes(f.id));
  const contacts = task.contactIDs.map(contact).filter(Boolean);
  const subDone = task.subtasks.filter((s) => s.isDone).length;
  const open = ui.openSubtasks.has(task.id);
  const sorted = [...task.dates].sort((a, b) => cmpDates(a.date, b.date));
  const dates = sorted.slice(0, 3).map((d) => {
    const target = d.moveTo && column(d.moveTo);
    const late = isOverdue(d, task);
    return `<div class="date-line ${late ? "overdue" : ""}">
      <span class="kind-icon kind-${esc(d.kind)}">${icon(KIND_ICONS[d.kind] || "alert")}</span>
      <span class="muted">${esc(kindTitle(d.kind))}</span>
      <span class="when">${esc(dateLabel(d.date, showsTime(d), true))}</span>
      ${target ? `<span class="move" style="--c:${esc(target.colorHex)}">→ ${esc(target.name)}</span>` : ""}
      ${d.note ? `<span class="muted note">${esc(d.note)}</span>` : ""}
      ${late ? `<span class="late">${t("已过期")}</span>` : ""}
    </div>`;
  }).join("");
  const autoMove = [...task.autoMoves].sort((a, b) => cmpDates(a.date, b.date))[0];
  const autoTarget = autoMove && column(autoMove.columnID);
  const prev = previousColumn(task), next = nextColumn(task);
  const bg = task.backgroundHex;
  return `<article class="card ${done ? "done" : ""}" data-task="${esc(task.id)}" draggable="true" style="--accent:${esc(accent)}${bg ? `;--card:${esc(bg)};--card-text:${contrastingText(bg)}` : ""}">
    <div class="card-body" data-act="edit">
      <div class="title-row">
        ${p.icon ? `<span class="prio">${esc(p.icon)}</span>` : `<span class="dot" style="background:${esc(p.colorHex)}"></span>`}
        <span class="title">${esc(task.title)}</span>
      </div>
      ${task.notes ? `<p class="notes">${esc(task.notes)}</p>` : ""}
      ${flags.length || tags.length ? `<div class="chips">${flags.map((f) => flagChip(f)).join("")}${tags.map((g) => tagChipHTML(g, { small: true })).join("")}</div>` : ""}
      ${contacts.length ? `<div class="meta-line"><span class="meta-icon">${icon("people")}</span><span class="people">${contacts.map((c) => `<button class="link" data-act="contact" data-id="${esc(c.id)}">${esc(c.name)}</button>`).join("")}</span></div>` : ""}
      ${dates ? `<div class="dates">${dates}${task.dates.length > 3 ? `<div class="faint small">${t("还有 {} 个日期", task.dates.length - 3)}</div>` : ""}</div>` : ""}
      ${autoTarget ? `<div class="meta-line" style="color:${esc(autoTarget.colorHex)}">⏩ ${esc(dateLabel(autoMove.date, autoMove.hasTime !== false))} → ${esc(autoTarget.name)}</div>` : ""}
      ${task.links.length ? `<div class="links">${task.links.slice(0, 3).map(linkHTML).join("")}${task.links.length > 3 ? `<div class="faint">${t("还有 {} 个附件", task.links.length - 3)}</div>` : ""}</div>` : ""}
      ${focusMinutes(task) > 0 ? `<div class="meta-line muted">${t("🍅 专注 {} 分钟", focusMinutes(task))}</div>` : ""}
      ${task.recurrence && task.recurrence !== "none" ? `<div class="meta-line muted"><span class="meta-icon">${icon("repeat")}</span>${esc(repeatTitle(task))}</div>` : ""}
      ${done && task.completedAt ? `<div class="meta-line completed"><span class="meta-icon">${icon("checkCircle")}</span>${t("完成于 {}", dateLabel(task.completedAt, false))}</div>` : ""}
    </div>
    ${task.subtasks.length ? `
      <div class="subtasks">
        <button class="sub-toggle" data-act="subs"><span class="chev ${open ? "open" : ""}">${icon("chevR")}</span><span class="meta-icon">${icon("checklist")}</span>${subDone}/${task.subtasks.length}
          <span class="bar"><span style="width:${(subDone / task.subtasks.length) * 100}%"></span></span></button>
        ${open ? task.subtasks.map((s) => `
          <button class="sub ${s.isDone ? "on" : ""}" data-act="sub" data-id="${esc(s.id)}">
            <span class="box">${s.isDone ? "✓" : ""}</span><span class="sub-title">${esc(s.title)}</span>
            ${s.date ? `<span class="sub-date ${subOverdue(s) ? "overdue" : ""}">${esc(dateLabel(s.date, s.hasTime))}</span>` : ""}
          </button>`).join("") : ""}
      </div>` : ""}
    <div class="card-foot">
      <button class="move-btn" data-act="left" ${prev ? `title="${esc(t("移到「{}」", prev.name))}"` : "disabled"}>${icon("chevL")}</button>
      <button class="move-btn" data-act="right" ${next ? `title="${esc(t("移到「{}」", next.name))}"` : "disabled"}>${icon("chevR")}</button>
    </div>
  </article>`;
}

const KIND_ICONS = { deadline: "alert", milestone: "flag", start: "play", reminder: "bell" };
const focusMinutes = (task) => task.focusSessions.reduce((n, s) => n + (s.minutes || 0), 0);
function contrastingText(hex) {
  const h = hex.replace("#", ""), n = parseInt(h.slice(0, 6), 16);
  const lum = (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
  return lum > 0.65 ? "#000" : "#fff";
}
function previousColumn(task) { const cs = B().columns, i = cs.findIndex((c) => c.id === task.columnID); return i > 0 ? cs[i - 1] : null; }
function nextColumn(task) { const cs = B().columns, i = cs.findIndex((c) => c.id === task.columnID); return i >= 0 && i < cs.length - 1 ? cs[i + 1] : null; }

/** A row in the editor's 附件和链接: name, then where it is (computer and folder, or the address). */
function linkEditRow(l) {
  if (l.url.startsWith("file://")) {
    const { device, path } = fileInfo(l);
    return `<div class="link-edit-row"><span class="meta-icon">${icon("clip")}</span><div class="link-text"><b>${esc(l.title)}</b>
      <span class="muted small">${icon("laptop")} ${esc(device)} · <span class="path">${esc(path)}</span></span></div>
      <button class="mini" data-act="file" data-path="${esc(path)}" data-device="${esc(device)}"><span class="link-name" hidden>${esc(l.title)}</span>${t("位置")}</button></div>`;
  }
  return `<div class="link-edit-row"><span class="meta-icon">${icon("link")}</span><div class="link-text"><b>${esc(l.title)}</b>
    <span class="muted small path">${esc(l.url)}</span></div><a class="mini" href="${esc(l.url)}" target="_blank" rel="noopener">${t("打开")}</a></div>`;
}

/** A file attached on a Mac: where it is ("MacBook Air · ~/Documents/…"). */
function fileInfo(l) {
  let path = l.url;
  try { path = decodeURIComponent(new URL(l.url).pathname); } catch {}
  path = path.replace(/^\/Users\/[^/]+/, "~").replace(/\/$/, "");
  return { device: l.device || t("电脑"), path };
}

function linkHTML(l) {
  const name = esc(l.title || l.url);
  if (l.url.startsWith("file://")) {
    const { device, path } = fileInfo(l);
    return `<button class="link-row file" data-act="file" data-path="${esc(path)}" data-device="${esc(device)}" title="${esc(`${device}：${path}`)}"><span class="meta-icon">${icon("clip")}</span><span class="link-name">${name}</span></button>`;
  }
  return `<a class="link-row" href="${esc(l.url)}" target="_blank" rel="noopener"><span class="meta-icon">${icon("link")}</span><span class="link-name">${name}</span></a>`;
}

const KINDS = ["deadline", "milestone", "start", "reminder"];
const kindTitle = (k) => ({ deadline: t("截止"), milestone: t("里程碑"), start: t("开始"), reminder: t("提醒") }[k] || k);
const kindIcon = (k) => ({ deadline: "⚠︎", milestone: "⚑", start: "▶︎", reminder: "🔔" }[k] || "•");

const RECURRENCES = ["none", "daily", "weekdays", "weekly", "biweekly", "monthly", "yearly"];
const recurrenceTitle = (r) => ({ none: t("不重复"), daily: t("每天"), weekdays: t("每个工作日"), weekly: t("每周"), biweekly: t("每两周"), monthly: t("每月"), yearly: t("每年"), custom: t("自定义") }[r] || r);
function repeatTitle(task) {
  if (task.recurrence !== "custom" || !task.repeatRule) return recurrenceTitle(task.recurrence);
  const r = task.repeatRule;
  const unit = { day: t("天|repeat"), week: t("周|repeat"), month: t("个月"), year: t("年|repeat") }[r.unit] || r.unit;
  const days = ["日", "一", "二", "三", "四", "五", "六"];
  const wd = r.unit === "week" && r.weekdays?.length ? ` · ${r.weekdays.map((d) => (isEnglish ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d - 1] : `周${days[d - 1]}`)).join(isEnglish ? ", " : "、")}` : "";
  return `${t("每 {} {}", r.interval || 1, unit)}${wd}`;
}

// MARK: - Board events

app.addEventListener("click", (e) => {
  const el = e.target.closest("[data-act]");
  if (!el || !store.board) return;
  const cardEl = el.closest("[data-task]");
  const task = cardEl && (taskByID(cardEl.dataset.task));
  switch (el.dataset.act) {
    case "tab":
      ui.columnID = el.dataset.id; save("bp.column", ui.columnID); renderBoard(); window.scrollTo(0, 0); break;
    case "new": openNew(el.dataset.column || currentColumn().id); break;
    case "settings": ui.settingsTab = "columns"; renderSettings(); break;
    case "group": {
      const key = `${el.dataset.column}|${el.dataset.key}`;
      const g = B().expandedGroups;
      B().expandedGroups = g.includes(key) ? g.filter((x) => x !== key) : [...g, key];
      changed(); break;
    }
    case "done": if (task) { toggleDone(task); changed(); } break;
    case "edit": if (task && !e.target.closest("a,button")) { ui.editing = task.id; renderEditor(); } break;
    case "subs": if (task) { ui.openSubtasks.has(task.id) ? ui.openSubtasks.delete(task.id) : ui.openSubtasks.add(task.id); renderBoard(); } break;
    case "sub": if (task) {
      const s = task.subtasks.find((x) => x.id === el.dataset.id);
      if (s) { s.isDone = !s.isDone; addHistory(task, "subtask", t(s.isDone ? "完成子任务「{}」" : "重新打开子任务「{}」", s.title)); task.updatedAt = nowISO(); changed(); }
    } break;
    case "contact": showContact(el.dataset.id, el); break;
    case "file": showFile(el); break;
    case "left": case "right": if (task) {
      const target = el.dataset.act === "left" ? previousColumn(task) : nextColumn(task);
      if (target) { moveTask(task, target.id); changed(); }
    } break;
    case "trash": ui.settingsTab = "trash"; renderSettings(); break;
    case "menu": showMenu(el, menuItems(el.dataset.menu, el.dataset.column)); break;
  }
});

// MARK: - Toolbar and column menus

const FONT_SCALES = [[0.85, "特小"], [0.92, "小"], [1.0, "标准"], [1.15, "大"], [1.3, "特大"], [1.45, "超大"], [1.6, "巨大"]];
const SORT_MODES = [["manual", "手动排序（拖动调整）"], ["priority", "按优先级"], ["date", "按日期"], ["created", "按创建时间"]];
const FOLD_MODES = [["off", "不折叠"], ["all", "整列折叠"], ["tag", "按标签折叠"], ["priority", "按优先级折叠"], ["date", "按日期折叠"]];
const WIDTHS = [[0, "自动"], [160, "很窄"], [220, "窄"], [300, "标准"], [380, "宽"], [480, "很宽"]];

/** Font size, like the Mac's 大小 menu (kept per device). */
function applyScale() {
  const saved = Number(load("bp.scale"));
  ui.scale = saved || (matchMedia("(max-width: 699px)").matches ? 1.2 : 1.15);
  document.documentElement.style.setProperty("--s", ui.scale);
}

function menuItems(kind, columnID) {
  const items = [];
  if (kind === "lang") {
    items.push({ label: "中文", on: !isEnglish, run: () => { save("bp.lang", "zh"); location.reload(); } });
    items.push({ label: "English", on: isEnglish, run: () => { save("bp.lang", "en"); location.reload(); } });
  } else if (kind === "size") {
    for (const [v, name] of FONT_SCALES) items.push({ label: t(name), on: Math.abs(ui.scale - v) < 0.001, run: () => { save("bp.scale", String(v)); applyScale(); render(); } });
  } else if (kind === "sort") {
    for (const [v, name] of SORT_MODES) items.push({ label: t(name), on: B().sortMode === v, run: () => { B().sortMode = v; changed(); } });
  } else if (kind === "tags") {
    const pick = (id) => () => { ui.tagFilter = id; save("bp.tagFilter", id); renderTools(); renderBoard(); };
    items.push({ label: t("全部标签"), on: !ui.tagFilter, run: pick(null) });
    if (B().tags.length) items.push("-");
    for (const g of B().tags) items.push({ html: tagChipHTML(g), on: ui.tagFilter === g.id, run: pick(g.id) });
  } else if (kind === "fold") {
    const c = column(columnID);
    if (!c) return items;
    const mode = c.foldMode || "off";
    items.push({ header: t("折叠方式") });
    for (const [v, name] of FOLD_MODES) items.push({ label: t(name), icon: FOLD_ICONS[v] === "compress" && v === "off" ? "list" : FOLD_ICONS[v], on: mode === v, run: () => { c.foldMode = v; changed(); } });
    if (mode !== "off") {
      items.push("-");
      const keys = () => foldGroups(c, tasksIn(c.id)).map((g) => `${c.id}|${g.key}`);
      items.push({ label: t("全部展开"), run: () => { B().expandedGroups = [...new Set([...B().expandedGroups, ...keys()])]; changed(); } });
      items.push({ label: t("全部折叠"), run: () => { const k = new Set(keys()); B().expandedGroups = B().expandedGroups.filter((x) => !k.has(x)); changed(); } });
      if (mode !== "all") items.push({ label: t("恢复默认分组顺序"), disabled: !(c.groupOrder || []).length, run: () => { c.groupOrder = []; changed(); } });
    }
    items.push("-");
    const count = B().tasks.filter((x) => x.columnID === c.id).length;
    items.push({ label: t("清空这一列…"), disabled: !count, run: () => {
      if (!confirm(t("这一列的 {} 个任务会移到「最近删除」，30 天内可以恢复。", count))) return;
      const now = nowISO();
      B().trash.push(...B().tasks.filter((x) => x.columnID === c.id).map((x) => ({ ...x, deletedAt: now })));
      B().tasks = B().tasks.filter((x) => x.columnID !== c.id);
      changed();
    } });
    items.push("-");
    items.push({ header: t("列宽") });
    for (const [v, name] of WIDTHS) items.push({ label: t(name), on: (c.width || 0) === v, run: () => { if (v) c.width = v; else delete c.width; changed(); } });
    if (c.width && !WIDTHS.some(([v]) => v === c.width)) items.push({ label: t("自定义（{}）", Math.round(c.width)), on: true, run: () => {} });
  }
  return items;
}

function showMenu(anchor, items) {
  const open = $(".menu");
  $(".popover")?.remove();
  open?.remove();
  if (open && open.dataset.for === anchor.dataset.menu + (anchor.dataset.column || "")) return;   // second click closes it
  const menu = document.createElement("div");
  menu.className = "popover menu";
  menu.dataset.for = anchor.dataset.menu + (anchor.dataset.column || "");
  menu.innerHTML = items.map((it, i) => it === "-" ? `<hr>` : it.header ? `<div class="menu-header">${esc(it.header)}</div>`
    : `<button class="menu-item" data-i="${i}" ${it.disabled ? "disabled" : ""}><span class="menu-check">${it.on ? "✓" : ""}</span>${it.icon ? `<span class="meta-icon">${icon(it.icon)}</span>` : ""}${it.html || esc(it.label)}</button>`).join("");
  menu.addEventListener("click", (e) => {
    const b = e.target.closest(".menu-item");
    if (!b) return;
    menu.remove();
    items[Number(b.dataset.i)].run();
  });
  document.body.appendChild(menu);
  drawTagShapes(menu);
  placePopover(menu, anchor);
}

function placePopover(pop, anchor) {
  const r = anchor.getBoundingClientRect();
  pop.style.left = `${Math.max(8, Math.min(r.left, innerWidth - pop.offsetWidth - 8)) + scrollX}px`;
  pop.style.top = `${Math.max(scrollY + 8, Math.min(r.bottom + 6 + scrollY, scrollY + innerHeight - pop.offsetHeight - 8))}px`;
}

/** A file attached on a Mac: which computer it's on and where; the path can be copied. */
function showFile(anchor) {
  $(".popover")?.remove();
  const pop = document.createElement("div");
  pop.className = "popover file-pop";
  const { device, path } = anchor.dataset;
  pop.innerHTML = `<b>${esc(anchor.querySelector(".link-name")?.textContent || "")}</b>
    <div class="file-where"><span class="meta-icon">${icon("laptop")}</span>${esc(device)}</div>
    <code class="file-path">${esc(path)}</code>
    <button class="pop-btn" data-copy>${t("复制路径")}</button>
    <span class="muted small">${t("文件在这台电脑上，要在电脑版 App 里打开。")}</span>`;
  pop.querySelector("[data-copy]").onclick = async (e) => {
    try { await navigator.clipboard.writeText(path); e.target.textContent = t("已复制"); } catch { e.target.textContent = t("复制失败"); }
  };
  document.body.appendChild(pop);
  placePopover(pop, anchor);
}

// Small line icons in the style of the Mac app's SF Symbols.
const ICONS = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevL: '<path d="m15 18-6-6 6-6"/>',
  chevR: '<path d="m9 18 6-6-6-6"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  globe: '<circle cx="12" cy="12" r="9.5"/><path d="M2.5 12h19M12 2.5c3.2 3.5 3.2 15.5 0 19M12 2.5c-3.2 3.5-3.2 15.5 0 19"/>',
  sort: '<path d="M7 20V4M3 8l4-4 4 4M17 4v16M13 16l4 4 4-4"/>',
  tag: '<path d="M3 4.5A1.5 1.5 0 0 1 4.5 3h6.4a2 2 0 0 1 1.4.6l8.4 8.4a2 2 0 0 1 0 2.8l-6.1 6.1a2 2 0 0 1-2.8 0L3.6 12.3a2 2 0 0 1-.6-1.4z"/><circle cx="8" cy="8" r="1.3" fill="currentColor"/>',
  sliders: '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
  trash: '<path d="M4 7h16M9 7V4.5h6V7M6 7l1 13h10l1-13M10 11v6M14 11v6"/>',
  clip: '<path d="m20.5 11.5-8.2 8.2a5.5 5.5 0 0 1-7.8-7.8l8.6-8.6a3.7 3.7 0 0 1 5.2 5.2l-8.6 8.6a1.8 1.8 0 0 1-2.6-2.6l7.9-7.9"/>',
  link: '<path d="M10 13.5a4.5 4.5 0 0 0 6.8.5l3-3a4.5 4.5 0 0 0-6.4-6.4l-1.7 1.7"/><path d="M14 10.5a4.5 4.5 0 0 0-6.8-.5l-3 3a4.5 4.5 0 0 0 6.4 6.4l1.7-1.7"/>',
  people: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.3c2.1.6 3.5 2.6 3.5 5.7"/>',
  bell: '<path d="M6 9a6 6 0 0 1 12 0c0 6 2.5 8 2.5 8h-17S6 15 6 9"/><path d="M10 20.5a2.2 2.2 0 0 0 4 0"/>',
  alert: '<circle cx="12" cy="12" r="9.5"/><path d="M12 7v6"/><circle cx="12" cy="16.5" r=".6" fill="currentColor"/>',
  flag: '<path d="M5 21V4" /><path d="M5 4.5c4-2.5 7 2.5 13 0V14c-6 2.5-9-2.5-13 0z" fill="currentColor"/>',
  play: '<circle cx="12" cy="12" r="9.5"/><path d="m10 8.5 5.5 3.5-5.5 3.5z" fill="currentColor"/>',
  repeat: '<path d="m17 2.5 3.5 3.5-3.5 3.5"/><path d="M3.5 11.5V10a4 4 0 0 1 4-4h13"/><path d="m7 21.5-3.5-3.5 3.5-3.5"/><path d="M20.5 12.5V14a4 4 0 0 1-4 4h-13"/>',
  checklist: '<path d="m3 6.5 1.8 1.8L8 5M3 15.5l1.8 1.8L8 14M12 7h9M12 16h9"/>',
  checkCircle: '<circle cx="12" cy="12" r="9.5" fill="currentColor" stroke="none"/><path d="m8 12.3 2.8 2.7L16 9.5" stroke="#fff"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  list: '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r=".8" fill="currentColor"/><circle cx="4.5" cy="12" r=".8" fill="currentColor"/><circle cx="4.5" cy="18" r=".8" fill="currentColor"/>',
  compress: '<rect x="3.5" y="9" width="17" height="6" rx="1.5"/><path d="m9 2.5 3 3 3-3M9 21.5l3-3 3 3"/>',
  seal: '<path d="m12 2.5 2.3 1.7 2.8-.2.9 2.7 2.3 1.6-.9 2.7.9 2.7-2.3 1.6-.9 2.7-2.8-.2L12 19.5l-2.3-1.7-2.8.2-.9-2.7-2.3-1.6.9-2.7-.9-2.7 2.3-1.6.9-2.7 2.8.2z" fill="currentColor" stroke="none"/><path d="m8.5 11.2 2.4 2.3 4.6-4.5" stroke="#fff"/>',
  laptop: '<rect x="4.5" y="5" width="15" height="10.5" rx="1.5"/><path d="M2 19h20"/>',
};
function icon(name) {
  return `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ""}</svg>`;
}

function toggleDone(task) {
  if (isDone(task)) {
    const back = B().columns.find((c) => !c.isDone);
    if (back) moveTask(task, back.id);
  } else {
    const done = B().columns.find((c) => c.isDone);
    if (done) moveTask(task, done.id);
  }
}

// Drag cards between columns (desktop).
app.addEventListener("dragstart", (e) => {
  const c = e.target.closest?.("[data-task]");
  if (c) { e.dataTransfer.setData("text/plain", c.dataset.task); e.dataTransfer.effectAllowed = "move"; c.classList.add("dragging"); }
});
app.addEventListener("dragend", (e) => e.target.closest?.("[data-task]")?.classList.remove("dragging"));
app.addEventListener("dragover", (e) => {
  const col = e.target.closest?.("[data-column].column");
  if (col) { e.preventDefault(); col.classList.add("drop"); }
});
app.addEventListener("dragleave", (e) => e.target.closest?.(".column")?.classList.remove("drop"));
app.addEventListener("drop", (e) => {
  const col = e.target.closest?.(".column");
  if (!col) return;
  e.preventDefault();
  col.classList.remove("drop");
  const task = taskByID(e.dataTransfer.getData("text/plain"));
  if (!task) return;
  const targetCard = e.target.closest("[data-task]");
  if (task.columnID !== col.dataset.column) moveTask(task, col.dataset.column);
  // Dropped on another card: place it just above that card (manual order).
  if (targetCard && targetCard.dataset.task !== task.id) {
    const list = tasksIn(col.dataset.column).filter((x) => x.id !== task.id);
    const i = list.findIndex((x) => x.id === targetCard.dataset.task);
    const above = list[i - 1], below = list[i];
    task.order = above ? ((above.order ?? 0) + (below.order ?? 0)) / 2 : (below.order ?? 0) - 1;
    if (B().sortMode !== "manual") B().sortMode = "manual";
  }
  changed();
});

// MARK: - Task editor

function openNew(columnID) {
  const task = {
    id: uuid(), title: "", notes: "", columnID, priorityID: B().defaultPriorityID, tagIDs: [], dates: [], subtasks: [],
    order: topOrder(columnID), history: [], createdAt: nowISO(), updatedAt: nowISO(), recurrence: "none",
    recurrenceSpawned: false, links: [], notificationsOff: false, flagIDs: [], contactIDs: [], autoMoves: [], focusSessions: [],
  };
  ui.newTask = task;
  ui.editing = task.id;
  renderEditor(true);
  setTimeout(() => $("#ed-title")?.focus(), 50);
}

/** The task being edited: in the board, or a new one not added until it has a title. */
function editingTask() {
  return taskByID(ui.editing) || (ui.newTask?.id === ui.editing ? ui.newTask : null);
}

/** After each edit in the editor. */
function edited(task, { rerender = false } = {}) {
  task.updatedAt = nowISO();
  if (!taskByID(task.id)) {
    if (!task.title.trim()) { if (rerender) renderEditor(true); return; }
    addHistory(task, "created", t("创建于「{}」", column(task.columnID)?.name || ""));
    B().tasks.push(task);
    ui.newTask = null;
  }
  changed();
  if (rerender) renderEditor(true);
}

function closeEditor() {
  ui.editing = null;
  ui.newTask = null;
  $("#modal").innerHTML = "";
  document.body.classList.remove("modal-open");
}

function renderEditor(force = false) {
  const task = editingTask();
  if (!task) return closeEditor();
  // Don't rebuild the form under the user's fingers while typing.
  const active = document.activeElement;
  if (!force && active && $("#modal")?.contains(active) && active.matches("input[type=text],input:not([type]),textarea") && $(".editor")?.dataset.task === task.id) return;
  const b = B();
  const exists = !!taskByID(task.id);
  document.body.classList.add("modal-open");
  const sameTask = $(".editor")?.dataset.task === task.id;
  const scroll = sameTask ? $(".editor .sheet-body").scrollTop : 0;
  $("#modal").innerHTML = `
  <div class="sheet-backdrop" data-ed="close"></div>
  <div class="sheet editor" data-task="${esc(task.id)}">
    <div class="sheet-head">
      <span class="saved">${exists ? `✓ ${t("已自动保存")}` : t("输入标题后自动创建")}</span>
      <button class="primary" data-ed="close">${t("完成")}</button>
    </div>
    <div class="sheet-body">
      <input id="ed-title" class="ed-title" type="text" placeholder="${t("要做什么？")}" value="${esc(task.title)}">
      <textarea id="ed-notes" rows="3" placeholder="${t("备注")}">${esc(task.notes)}</textarea>

      <div class="row2">
        <label>${t("状态")}<select id="ed-column">${b.columns.map((c) => `<option value="${esc(c.id)}" ${c.id === task.columnID ? "selected" : ""}>${esc(label(c))}</option>`).join("")}</select></label>
        <label>${t("优先级")}<select id="ed-priority">${b.priorities.map((p) => `<option value="${esc(p.id)}" ${p.id === priorityOf(task).id ? "selected" : ""}>${esc(label(p))}</option>`).join("")}</select></label>
      </div>

      <h3>${t("进展")}</h3>
      <div class="chips">${b.flags.map((f) => `<button data-ed="flag" data-id="${esc(f.id)}">${flagChip(f, task.flagIDs.includes(f.id) ? "" : "off")}</button>`).join("")}</div>

      <h3>${t("标签")}</h3>
      <div class="chips">${b.tags.map((g) => `<button data-ed="tag" data-id="${esc(g.id)}">${tagChip(g, task.tagIDs.includes(g.id) ? "" : "off")}</button>`).join("")}</div>
      <div class="inline-add"><input id="ed-newtag" type="text" placeholder="${t("新标签")}"><button data-ed="addtag">${t("添加")}</button></div>
      ${ui.packMessage ? `<p class="muted small">${esc(ui.packMessage)}</p>` : ""}

      <h3>${t("联系人 / 合作人")}</h3>
      <div class="chips">${task.contactIDs.map(contact).filter(Boolean).map((c) => `
        <span class="chip person"><button class="link" data-ed="showcontact" data-id="${esc(c.id)}">${esc(c.name)}</button><button class="x" data-ed="rmcontact" data-id="${esc(c.id)}" aria-label="${t("移除")}">×</button></span>`).join("")}</div>
      <div class="inline-add">
        <input id="ed-contact" type="text" list="contact-names" placeholder="${t("输入名字，回车添加")}">
        <datalist id="contact-names">${b.contacts.filter((c) => !task.contactIDs.includes(c.id)).map((c) => `<option value="${esc(c.name)}">`).join("")}</datalist>
        <button data-ed="addcontact">${t("添加")}</button>
      </div>

      <h3>${task.subtasks.length ? t("子任务（{}/{}）", task.subtasks.filter((s) => s.isDone).length, task.subtasks.length) : t("子任务")}</h3>
      <div class="sub-edit">${task.subtasks.map((s, i) => `
        <div class="sub-row" data-sub="${esc(s.id)}">
          <button class="box ${s.isDone ? "on" : ""}" data-ed="subdone">${s.isDone ? "✓" : ""}</button>
          <input type="text" class="sub-title-in ${s.isDone ? "struck" : ""}" value="${esc(s.title)}" data-field="subtitle">
          ${s.date ? `<input type="${s.hasTime ? "datetime-local" : "date"}" value="${inputValue(s.date, s.hasTime)}" data-field="subdate">
            <button class="mini" data-ed="subtime">${s.hasTime ? t("去掉时间") : t("+ 时间")}</button>`
          : `<button class="mini" data-ed="subadddate">📅</button>`}
          <span class="sub-actions">
            ${s.date ? `<button class="mini" data-ed="subrmdate" title="${t("去掉日期")}">⌫</button>` : ""}
            <button class="mini" data-ed="subup" ${i === 0 ? "disabled" : ""}>↑</button>
            <button class="mini danger" data-ed="subrm" aria-label="${t("删除")}">×</button>
          </span>
        </div>`).join("")}
      </div>
      <div class="inline-add"><input id="ed-newsub" type="text" placeholder="${t("输入子任务，回车添加")}"><button data-ed="addsub">${t("添加")}</button></div>
      ${b.subtaskPacks.length ? `<select id="ed-pack"><option value="">📦 ${t("应用子任务包…")}</option>${b.subtaskPacks.map((p) => `<option value="${esc(p.id)}">${esc(label(p))}（${p.items.length}）</option>`).join("")}</select>` : ""}

      <h3>${t("日期")}</h3>
      ${task.dates.map((d) => `
        <div class="date-edit" data-date="${esc(d.id)}">
          <div class="line">
            <select data-field="kind">${KINDS.map((k) => `<option value="${k}" ${k === d.kind ? "selected" : ""}>${kindIcon(k)} ${kindTitle(k)}</option>`).join("")}</select>
            <input type="${showsTime(d) ? "datetime-local" : "date"}" value="${inputValue(d.date, showsTime(d))}" data-field="date">
            ${d.kind !== "reminder" ? `<button class="mini" data-ed="datetime">${d.hasTime ? t("去掉时间") : t("+ 时间")}</button>` : ""}
            <button class="mini danger" data-ed="rmdate" aria-label="${t("删除")}">×</button>
          </div>
          <div class="line">
            <input type="text" placeholder="${t("说明（可选）")}" value="${esc(d.note || "")}" data-field="note">
            <select data-field="moveTo" class="move-select">
              <option value="">${t("+ 到时移动")}</option>
              ${b.columns.map((c) => `<option value="${esc(c.id)}" ${c.id === d.moveTo ? "selected" : ""}>→ ${esc(c.name)}</option>`).join("")}
            </select>
          </div>
        </div>`).join("")}
      <select id="ed-adddate"><option value="">📅 ${t("添加日期…")}</option>${KINDS.map((k) => `<option value="${k}">${kindIcon(k)} ${kindTitle(k)}</option>`).join("")}</select>

      <h3>${t("重复")}</h3>
      <select id="ed-repeat">
        ${RECURRENCES.map((r) => `<option value="${r}" ${r === task.recurrence ? "selected" : ""}>${recurrenceTitle(r)}</option>`).join("")}
        ${task.recurrence === "custom" ? `<option value="custom" selected>${esc(repeatTitle(task))}</option>` : ""}
      </select>
      ${task.recurrence !== "none" ? `<p class="muted small">${t("完成后会自动生成下一次（由电脑版 App 生成）。")}</p>` : ""}

      ${task.links.length ? `<h3>${t("附件和链接（{}）", task.links.length)}</h3><div class="links-edit">${task.links.map(linkEditRow).join("")}</div>` : ""}

      ${task.history.length ? `<details class="history"><summary>${t("历史记录（{}）", task.history.length)}</summary>
        ${[...task.history].reverse().slice(0, 50).map((h) => `<div><span class="muted">${esc(dateLabel(h.date, true))}</span> ${esc(h.text)}</div>`).join("")}</details>` : ""}

      ${exists ? `<button class="danger-btn" data-ed="delete">${t("删除任务")}</button>` : ""}
    </div>
  </div>`;
  $(".editor .sheet-body").scrollTop = scroll;
}

function inputValue(isoString, withTime) {
  const d = new Date(isoString);
  const p = (n) => String(n).padStart(2, "0");
  const day = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  return withTime ? `${day}T${p(d.getHours())}:${p(d.getMinutes())}` : day;
}

/** From a date / datetime-local input: date-only values mean local midnight (as on the Mac). */
function fromInput(value, withTime) {
  if (!value) return null;
  const d = withTime ? new Date(value) : new Date(`${value}T00:00`);
  return isNaN(d) ? null : iso(d);
}

document.addEventListener("input", (e) => {
  const task = ui.editing && editingTask();
  if (!task || !e.target.closest(".editor")) return;
  const el = e.target;
  if (el.id === "ed-title") { task.title = el.value; edited(task); renderEditorHead(task); }
  else if (el.id === "ed-notes") { task.notes = el.value; edited(task); }
  else if (el.dataset.field === "subtitle") {
    const s = task.subtasks.find((x) => x.id === el.closest("[data-sub]").dataset.sub);
    if (s) { s.title = el.value; edited(task); }
  } else if (el.dataset.field === "note") {
    const d = task.dates.find((x) => x.id === el.closest("[data-date]").dataset.date);
    if (d) { d.note = el.value; edited(task); }
  }
});

function renderEditorHead(task) {
  const el = $(".editor .saved");
  if (el) el.textContent = taskByID(task.id) ? `✓ ${t("已自动保存")}` : t("输入标题后自动创建");
}

document.addEventListener("change", (e) => {
  const task = ui.editing && editingTask();
  if (!task || !e.target.closest(".editor")) return;
  const el = e.target;
  if (el.id === "ed-column") { if (taskByID(task.id)) moveTask(task, el.value); else task.columnID = el.value; edited(task, { rerender: true }); }
  else if (el.id === "ed-priority") { task.priorityID = el.value; edited(task); }
  else if (el.id === "ed-repeat") { task.recurrence = el.value; if (el.value !== "custom") delete task.repeatRule; edited(task, { rerender: true }); }
  else if (el.id === "ed-pack") {
    const pack = B().subtaskPacks.find((p) => p.id === el.value);
    if (pack) { const n = applyPack(task, pack); ui.packMessage = n ? t("已添加「{}」的 {} 个子任务", pack.name, n) : t("「{}」的子任务都已经有了", pack.name); }
    edited(task, { rerender: true });
  } else if (el.id === "ed-adddate") {
    const kind = el.value;
    if (kind) {
      const d = new Date();
      if (kind === "reminder") { d.setMinutes(0, 0, 0); d.setHours(d.getHours() + 1); } else d.setHours(0, 0, 0, 0);
      task.dates.push({ id: uuid(), kind, date: iso(d), note: "", hasTime: kind === "reminder" });
      edited(task, { rerender: true });
    }
  } else if (el.dataset.field === "subdate") {
    const s = task.subtasks.find((x) => x.id === el.closest("[data-sub]").dataset.sub);
    const v = fromInput(el.value, s?.hasTime);
    if (s && v) { s.date = v; edited(task); }
  } else if (el.closest("[data-date]")) {
    const d = task.dates.find((x) => x.id === el.closest("[data-date]").dataset.date);
    if (!d) return;
    if (el.dataset.field === "kind") { d.kind = el.value; if (d.kind === "reminder") d.hasTime = true; edited(task, { rerender: true }); }
    else if (el.dataset.field === "date") { const v = fromInput(el.value, showsTime(d)); if (v) { d.date = v; edited(task); } }
    else if (el.dataset.field === "moveTo") { if (el.value) d.moveTo = el.value; else delete d.moveTo; edited(task); }
  }
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") { if (ui.settingsTab) closeSettings(); else if (ui.editing) closeEditor(); $(".popover")?.remove(); return; }
  if (e.key !== "Enter" || e.isComposing) return;
  const id = e.target.id;
  if (id === "ed-newsub") { e.preventDefault(); clickEd("addsub"); }
  else if (id === "ed-newtag") { e.preventDefault(); clickEd("addtag"); }
  else if (id === "ed-contact") { e.preventDefault(); clickEd("addcontact"); }
  else if (id === "ed-title") { e.preventDefault(); $("#ed-notes")?.focus(); }
});
const clickEd = (name) => $(`.editor [data-ed="${name}"]`)?.click();

document.addEventListener("click", (e) => {
  const el = e.target.closest("[data-ed]");
  if (!el) { if (!e.target.closest(".popover,[data-act=contact],[data-act=menu],[data-act=file],[data-ed=showcontact]")) $(".popover")?.remove(); return; }
  const task = editingTask();
  if (el.dataset.ed === "close") { closeEditor(); return; }
  if (!task) return;
  const sub = el.closest("[data-sub]") && task.subtasks.find((x) => x.id === el.closest("[data-sub]").dataset.sub);
  const date = el.closest("[data-date]") && task.dates.find((x) => x.id === el.closest("[data-date]").dataset.date);
  switch (el.dataset.ed) {
    case "flag": toggleIn(task.flagIDs, el.dataset.id); break;
    case "tag":
      if (toggleIn(task.tagIDs, el.dataset.id)) packsForTag(task, el.dataset.id);
      break;
    case "addtag": {
      const name = $("#ed-newtag").value.trim();
      if (!name) return;
      let g = B().tags.find((x) => x.name === name);
      if (!g) { g = { id: uuid(), name, colorHex: PALETTE[B().tags.length % PALETTE.length], icon: "" }; B().tags.push(g); }
      if (!task.tagIDs.includes(g.id)) { task.tagIDs.push(g.id); packsForTag(task, g.id); }
      break;
    }
    case "addcontact": {
      const name = $("#ed-contact").value.trim();
      if (!name) return;
      let c = B().contacts.find((x) => x.name.toLowerCase() === name.toLowerCase());
      if (!c) { c = { id: uuid(), name, email: "", phone: "" }; B().contacts.push(c); }
      if (!task.contactIDs.includes(c.id)) task.contactIDs.push(c.id);
      break;
    }
    case "rmcontact": task.contactIDs = task.contactIDs.filter((x) => x !== el.dataset.id); break;
    case "showcontact": showContact(el.dataset.id, el); return;
    case "addsub": {
      const title = $("#ed-newsub").value.trim();
      if (!title) return;
      task.subtasks.push({ id: uuid(), title, isDone: false, hasTime: false });
      addHistory(task, "subtask", t("添加子任务「{}」", title));
      edited(task, { rerender: true });
      setTimeout(() => $("#ed-newsub")?.focus(), 0);
      return;
    }
    case "subdone": if (sub) { sub.isDone = !sub.isDone; addHistory(task, "subtask", t(sub.isDone ? "完成子任务「{}」" : "重新打开子任务「{}」", sub.title)); } break;
    case "subrm": if (sub) { task.subtasks = task.subtasks.filter((x) => x !== sub); addHistory(task, "subtask", t("删除子任务「{}」", sub.title)); } break;
    case "subup": if (sub) { const i = task.subtasks.indexOf(sub); if (i > 0) task.subtasks.splice(i - 1, 0, ...task.subtasks.splice(i, 1)); } break;
    case "subadddate": if (sub) { sub.date = iso(startOfDay(new Date())); sub.hasTime = false; } break;
    case "subrmdate": if (sub) { delete sub.date; sub.hasTime = false; } break;
    case "subtime": if (sub) { sub.hasTime = !sub.hasTime; if (!sub.hasTime) sub.date = iso(startOfDay(new Date(sub.date))); else { const d = new Date(sub.date); d.setHours(9); sub.date = iso(d); } } break;
    case "datetime": if (date) { date.hasTime = !date.hasTime; if (!date.hasTime) date.date = iso(startOfDay(new Date(date.date))); else { const d = new Date(date.date); d.setHours(9); date.date = iso(d); } } break;
    case "rmdate": if (date) task.dates = task.dates.filter((x) => x !== date); break;
    case "delete":
      if (!confirm(t("删除「{}」？30 天内可以在设置 →「最近删除」里恢复。", task.title))) return;
      B().tasks = B().tasks.filter((x) => x.id !== task.id);
      B().trash.push({ ...task, deletedAt: nowISO() });
      closeEditor();
      changed();
      return;
    default: return;
  }
  edited(task, { rerender: true });
});

function toggleIn(list, id) {
  const i = list.indexOf(id);
  if (i >= 0) { list.splice(i, 1); return false; }
  list.push(id);
  return true;
}

function applyPack(task, pack) {
  let added = 0;
  for (const item of pack.items) {
    const title = item.trim();
    if (!title || task.subtasks.some((s) => s.title === title)) continue;
    task.subtasks.push({ id: uuid(), title, isDone: false, hasTime: false });
    added++;
  }
  return added;
}

/** Adding a tag also adds the subtask packs linked to it. */
function packsForTag(task, tagID) {
  const packs = B().subtaskPacks.filter((p) => (p.autoTagIDs || []).includes(tagID));
  const added = packs.reduce((n, p) => n + applyPack(task, p), 0);
  if (added) ui.packMessage = t("已按标签自动添加 {} 个子任务（{}）", added, packs.map((p) => p.name).join("、"));
}

const PALETTE = ["#5B85F5", "#F79E33", "#40B873", "#9B6CF0", "#E5534B", "#2BB3C0", "#E86FA8", "#8D99AE"];

/** Email / call for a contact. */
function showContact(id, anchor) {
  const c = contact(id);
  if (!c) return;
  $(".popover")?.remove();
  const pop = document.createElement("div");
  pop.className = "popover";
  pop.innerHTML = `<b>${esc(c.name)}</b>
    ${c.email ? `<a class="pop-btn" href="mailto:${esc(c.email)}">✉︎ ${esc(c.email)}</a>` : ""}
    ${c.phone ? `<a class="pop-btn" href="tel:${esc(c.phone.replace(/\s/g, ""))}">☎︎ ${esc(c.phone)}</a>` : ""}
    ${!c.email && !c.phone ? `<span class="muted small">${t("还没有邮箱和电话，可以在设置 →「联系人」里添加。")}</span>` : ""}`;
  document.body.appendChild(pop);
  placePopover(pop, anchor || document.activeElement || document.body);
}

// MARK: - Settings

const SETTINGS_TABS = [
  ["columns", "状态"], ["tags", "标签"], ["priorities", "优先级"], ["packs", "子任务包"],
  ["flags", "进展"], ["contacts", "联系人"], ["trash", "最近删除"], ["account", "账号"],
];

function closeSettings() {
  ui.settingsTab = null;
  $("#modal").innerHTML = "";
  document.body.classList.remove("modal-open");
}

function renderSettings(force = false) {
  const active = document.activeElement;
  if (!force && active && $("#modal")?.contains(active) && active.matches("input[type=text],input[type=email],input[type=tel],input:not([type]),textarea")) return;
  document.body.classList.add("modal-open");
  const b = B();
  const tab = ui.settingsTab;
  const scroll = $(".settings .sheet-body")?.scrollTop || 0;
  $("#modal").innerHTML = `
  <div class="sheet-backdrop" data-st="close"></div>
  <div class="sheet settings">
    <div class="sheet-head"><b>${t("设置")}</b><button class="primary" data-st="close">${t("完成")}</button></div>
    <nav class="seg">${SETTINGS_TABS.map(([k, n]) => `<button class="${k === tab ? "on" : ""}" data-st="tab" data-id="${k}">${t(n)}</button>`).join("")}</nav>
    <div class="sheet-body">${settingsBody(tab, b)}</div>
  </div>`;
  $(".settings .sheet-body").scrollTop = scroll;
}

function listEditor(kind, items, fields, extra = () => "") {
  return `<div class="list-edit">${items.map((x, i) => `
    <div class="list-row" data-kind="${kind}" data-id="${esc(x.id)}">
      ${fields.map((f) => fieldHTML(f, x)).join("")}
      ${extra(x)}
      <span class="row-actions">
        <button class="mini" data-st="up" ${i === 0 ? "disabled" : ""} aria-label="${t("上移")}">↑</button>
        <button class="mini danger" data-st="remove" aria-label="${t("删除")}">×</button>
      </span>
    </div>`).join("")}</div>
    <button class="add-row" data-st="add" data-kind="${kind}">＋ ${t("添加")}</button>`;
}

function fieldHTML(f, x) {
  const v = x[f.key];
  switch (f.type) {
    case "icon": return `<input class="icon-in" type="text" data-key="${f.key}" value="${esc(v || "")}" placeholder="🙂" maxlength="4">`;
    case "color": return `<input type="color" data-key="${f.key}" value="${esc(v || "#888888")}">`;
    case "check": return `<label class="check-label"><input type="checkbox" data-key="${f.key}" ${v ? "checked" : ""}> ${f.label}</label>`;
    case "select": return `<select data-key="${f.key}">${f.options.map(([val, name]) => `<option value="${val}" ${val === (v || f.options[0][0]) ? "selected" : ""}>${name}</option>`).join("")}</select>`;
    default: return `<input class="${f.cls || "name-in"}" type="${f.type || "text"}" data-key="${f.key}" value="${esc(v || "")}" placeholder="${esc(f.placeholder || "")}">`;
  }
}

function settingsBody(tab, b) {
  switch (tab) {
    case "columns":
      return `<p class="muted small">${t("「完成」状态里的任务算作已完成。")}</p>` + listEditor("columns", b.columns, [
        { key: "icon", type: "icon" }, { key: "name", placeholder: t("名称") }, { key: "colorHex", type: "color" },
        { key: "isDone", type: "check", label: t("完成") },
        { key: "foldMode", type: "select", options: [["off", t("不折叠")], ["all", t("整列折叠")], ["tag", t("按标签折叠")], ["priority", t("按优先级折叠")], ["date", t("按日期折叠")]] },
      ]) + `<h3>${t("排序")}</h3><select data-st="sort">${[["manual", t("手动排序（拖动调整）")], ["priority", t("按优先级")], ["date", t("按日期")], ["created", t("按创建时间")]]
        .map(([v, n]) => `<option value="${v}" ${b.sortMode === v ? "selected" : ""}>${n}</option>`).join("")}</select>`;
    case "tags":
      return listEditor("tags", b.tags, [{ key: "icon", type: "icon" }, { key: "name", placeholder: t("名称") }, { key: "colorHex", type: "color" }]);
    case "priorities":
      return `<p class="muted small">${t("排在上面的更重要。")}</p>` + listEditor("priorities", b.priorities,
        [{ key: "icon", type: "icon" }, { key: "name", placeholder: t("名称") }, { key: "colorHex", type: "color" }],
        (p) => `<label class="check-label"><input type="radio" name="defprio" data-st="defprio" value="${esc(p.id)}" ${b.defaultPriorityID === p.id ? "checked" : ""}> ${t("默认")}</label>`);
    case "packs":
      return listEditor("subtaskPacks", b.subtaskPacks, [{ key: "icon", type: "icon" }, { key: "name", placeholder: t("名称") }], (p) => `
        <textarea class="pack-items" data-key="items" rows="${Math.max(2, p.items.length)}" placeholder="${t("每行一个子任务")}">${esc(p.items.join("\n"))}</textarea>
        <div class="chips pack-tags"><span class="muted small">${t("加这些标签时自动添加：")}</span>${b.tags.map((g) => `<button data-st="packtag" data-tag="${esc(g.id)}">${tagChip(g, (p.autoTagIDs || []).includes(g.id) ? "" : "off")}</button>`).join("")}</div>`);
    case "flags":
      return listEditor("flags", b.flags, [{ key: "icon", type: "icon" }, { key: "name", placeholder: t("名称") }, { key: "colorHex", type: "color" }]);
    case "contacts":
      return listEditor("contacts", [...b.contacts].sort((x, y) => x.name.localeCompare(y.name)), [
        { key: "name", placeholder: t("名字") }, { key: "email", type: "email", placeholder: t("邮箱"), cls: "wide-in" }, { key: "phone", type: "tel", placeholder: t("电话"), cls: "wide-in" }]);
    case "trash":
      if (!b.trash.length) return `<p class="muted">${t("最近删除里没有任务。")}</p>`;
      return `<p class="muted small">${t("删除的任务保留 30 天。")}</p>` + [...b.trash].sort((x, y) => cmpDates(y.deletedAt, x.deletedAt)).map((x) => `
        <div class="list-row" data-trash="${esc(x.id)}"><span class="name-in">${esc(x.title)}</span>
          <span class="muted small">${x.deletedAt ? esc(dateLabel(x.deletedAt, false)) : ""}</span>
          <button class="mini" data-st="restore">${t("恢复")}</button></div>`).join("");
    case "account":
      return `<p>${t("已登录：")}<b>${esc(store.email || "")}</b></p>
        <p class="muted small">${t("电脑版 App 在设置 →「云同步」里登录同一个账号，就会和这里自动同步。")}</p>
        <p class="muted small">${t("手机上：用 Safari 打开这个网址，点分享按钮 →「添加到主屏幕」，就能像 App 一样打开。")}</p>
        <h3>${t("修改密码")}</h3>
        <input id="pw-old" type="password" placeholder="${t("当前密码")}" autocomplete="current-password">
        <input id="pw-new" type="password" placeholder="${t("新密码（至少 8 位）")}" autocomplete="new-password">
        <button data-st="password">${t("修改密码")}</button> <span id="pw-msg" class="muted small"></span>
        <h3></h3>
        <button class="danger-btn" data-st="signout">${t("退出登录")}</button>`;
  }
  return "";
}

const SETTINGS_KEY = { columns: "columns", tags: "tags", priorities: "priorities", subtaskPacks: "subtaskPacks", flags: "flags", contacts: "contacts" };

document.addEventListener("input", (e) => {
  const row = e.target.closest(".settings [data-kind]");
  if (!row || !e.target.dataset.key) return;
  const list = B()[SETTINGS_KEY[row.dataset.kind]];
  const item = list.find((x) => x.id === row.dataset.id);
  if (!item) return;
  const el = e.target;
  if (el.type === "checkbox") item[el.dataset.key] = el.checked;
  else if (el.dataset.key === "items") item.items = el.value.split("\n").map((s) => s.trim()).filter(Boolean);
  else item[el.dataset.key] = el.value;
  changed();
});

document.addEventListener("change", (e) => {
  if (e.target.matches(".settings select[data-key]")) { e.target.dispatchEvent(new Event("input", { bubbles: true })); return; }
  if (e.target.dataset.st === "sort") { B().sortMode = e.target.value; changed(); }
  if (e.target.dataset.st === "defprio") { B().defaultPriorityID = e.target.value; changed(); }
});

document.addEventListener("click", async (e) => {
  const el = e.target.closest("[data-st]");
  if (!el || el.tagName === "SELECT" || el.type === "radio") return;
  const b = B();
  const row = el.closest("[data-kind]");
  const kind = row?.dataset.kind || el.dataset.kind;
  const list = kind && b[SETTINGS_KEY[kind]];
  switch (el.dataset.st) {
    case "close": closeSettings(); return;
    case "tab": ui.settingsTab = el.dataset.id; renderSettings(true); return;
    case "add": {
      const color = PALETTE[list.length % PALETTE.length];
      const item = { columns: { name: t("新状态"), colorHex: color, icon: "", isDone: false, foldMode: "off", groupOrder: [] },
        tags: { name: t("新标签"), colorHex: color, icon: "" }, priorities: { name: t("新优先级"), colorHex: color, icon: "" },
        subtaskPacks: { name: t("新子任务包"), icon: "📦", items: [], autoTagIDs: [] }, flags: { name: t("新进展"), colorHex: color, icon: "" },
        contacts: { name: t("新联系人"), email: "", phone: "" } }[kind];
      list.push({ id: uuid(), ...item });
      break;
    }
    case "up": {
      const i = list.findIndex((x) => x.id === row.dataset.id);
      if (i > 0) list.splice(i - 1, 0, ...list.splice(i, 1));
      break;
    }
    case "remove": {
      const item = list.find((x) => x.id === row.dataset.id);
      if (!item || !removeSetting(kind, item)) return;
      break;
    }
    case "packtag": {
      const p = b.subtaskPacks.find((x) => x.id === row.dataset.id);
      p.autoTagIDs ||= [];
      toggleIn(p.autoTagIDs, el.dataset.tag);
      break;
    }
    case "restore": {
      const id = el.closest("[data-trash]").dataset.trash;
      const task = b.trash.find((x) => x.id === id);
      b.trash = b.trash.filter((x) => x.id !== id);
      delete task.deletedAt;
      if (!column(task.columnID)) task.columnID = b.columns[0].id;
      task.order = topOrder(task.columnID);
      b.tasks.push(task);
      break;
    }
    case "password": {
      const r = await api("POST", "/api/password", { oldPassword: $("#pw-old").value, newPassword: $("#pw-new").value })
        .catch(() => ({ status: 0, body: { error: "network" } }));
      $("#pw-msg").textContent = r.status === 200 ? t("密码已修改") : r.body.error === "password_short" ? t("新密码至少 8 位") : r.body.error === "network" ? t("连不上服务器，请检查网络") : t("当前密码不对");
      return;
    }
    case "signout":
      if (confirm(t("退出登录？"))) {
        if (store.dirty) await sync();   // send the last edits first
        if (store.dirty && !confirm(t("还有改动没传到服务器（可能没联网），退出后会丢失。仍然退出？"))) return;
        await api("POST", "/api/logout").catch(() => {});
        signOut();
      }
      return;
    default: return;
  }
  changed();
});

function removeSetting(kind, item) {
  const b = B();
  const used = (key) => b.tasks.filter((x) => x[key].includes(item.id)).length;
  if (kind === "columns") {
    if (b.columns.length <= 1) { alert(t("至少要保留一个状态。")); return false; }
    const n = b.tasks.filter((x) => x.columnID === item.id).length;
    const fallback = b.columns.find((c) => c.id !== item.id);
    if (!confirm(n ? t("删除状态「{}」？里面的 {} 个任务会移到「{}」。", item.name, n, fallback.name) : t("删除状态「{}」？", item.name))) return false;
    for (const x of b.tasks) if (x.columnID === item.id) x.columnID = fallback.id;
  } else if (kind === "priorities") {
    if (b.priorities.length <= 1) return false;
    if (!confirm(t("删除「{}」？", item.name))) return false;
    if (b.defaultPriorityID === item.id) b.defaultPriorityID = b.priorities.find((p) => p.id !== item.id).id;
    for (const x of b.tasks) if (x.priorityID === item.id) x.priorityID = b.defaultPriorityID;
  } else {
    const key = { tags: "tagIDs", flags: "flagIDs", contacts: "contactIDs" }[kind];
    const n = key ? used(key) : 0;
    if (!confirm(n ? t("删除「{}」？它会从 {} 个任务上移除。", item.name, n) : t("删除「{}」？", item.name))) return false;
    if (key) for (const x of b.tasks) x[key] = x[key].filter((id) => id !== item.id);
    if (kind === "tags") for (const p of b.subtaskPacks) p.autoTagIDs = (p.autoTagIDs || []).filter((id) => id !== item.id);
  }
  const list = b[SETTINGS_KEY[kind]];
  list.splice(list.indexOf(item), 1);
  return true;
}

// MARK: - Sign in

let signUpMode = false;
function renderSignIn() {
  document.body.classList.remove("modal-open");
  app.innerHTML = `
  <div class="signin">
    <img class="logo" src="/icon-192.png" alt="">
    <h1>Best Planner</h1>
    <p class="muted">${signUpMode ? t("注册一个账号，手机、电脑和网页都能用。") : t("登录后，手机、电脑和网页上的任务会自动同步。")}</p>
    <form id="signin-form">
      <input id="si-email" type="text" autocapitalize="none" autocorrect="off" spellcheck="false" placeholder="${t("账号（邮箱或用户名）")}" autocomplete="username" value="${esc(store.email || "")}" required>
      <input id="si-password" type="password" placeholder="${signUpMode ? t("密码（至少 8 位）") : t("密码")}" autocomplete="${signUpMode ? "new-password" : "current-password"}" required>
      ${signUpMode ? `<input id="si-invite" type="text" placeholder="${t("邀请码")}" autocomplete="off" required>` : ""}
      <button class="primary big" id="si-submit" type="submit">${signUpMode ? t("注册") : t("登录")}</button>
      <p id="si-msg" class="error"></p>
    </form>
    <button class="link" id="si-switch">${signUpMode ? t("已经有账号？登录") : t("还没有账号？注册")}</button>
    <p class="muted small lang"><button class="link" id="si-lang">${isEnglish ? "中文" : "English"}</button></p>
  </div>`;
  $("#si-switch").onclick = () => { signUpMode = !signUpMode; renderSignIn(); };
  $("#si-lang").onclick = () => { save("bp.lang", isEnglish ? "zh" : "en"); location.reload(); };
  $("#signin-form").onsubmit = async (e) => {
    e.preventDefault();
    const msg = $("#si-msg");
    msg.textContent = "";
    const button = $("#si-submit"), label = button.textContent;
    if (button.disabled) return;
    button.disabled = true;
    button.textContent = signUpMode ? t("正在注册…") : t("正在登录…");
    const done = () => { button.disabled = false; button.textContent = label; };
    const data = { email: $("#si-email").value, password: $("#si-password").value, invite: $("#si-invite")?.value };
    try {
      const r = await api("POST", signUpMode ? "/api/signup" : "/api/login", data);
      if (r.status !== 200) {
        msg.textContent = { wrong: t("密码不对，还可以再试 {} 次", r.body.left ?? 1), no_account: t("没有这个账号，请检查拼写，或先注册"), locked: t("密码错误次数太多，请 15 分钟后再试"), email_taken: t("这个账号已经被注册了"),
          email: t("账号格式不对：用邮箱，或 3–32 位字母、数字、. _ -"), password_short: t("密码至少 8 位"), invite: t("邀请码不对") }[r.body.error] || t("出错了，请稍后再试");
        done();
        msg.classList.remove("shake"); void msg.offsetWidth; msg.classList.add("shake");
        if (r.body.error === "wrong") { $("#si-password").select(); }
        return;
      }
      if (signUpMode) {
        // Signed up: say so, then go to the sign-in page (account filled in) after 5 seconds.
        // The session the sign-up created isn't kept; signing in makes a new one.
        fetch("/api/logout", { method: "POST", headers: { Authorization: `Bearer ${r.body.token}` } }).catch(() => {});
        store.email = r.body.email;
        save("bp.email", store.email);
        signUpMode = false;
        return renderSignedUp();
      }
      store.token = r.body.token;
      store.email = r.body.email;
      save("bp.token", store.token);
      save("bp.email", store.email);
      // Ask the browser not to clear the sign-in and cached board when space runs low.
      navigator.storage?.persist?.().catch(() => {});
      Object.assign(store, { board: null, base: null, version: 0, dirty: false });
      app.innerHTML = "";
      render();
      await sync();
    } catch {
      done();
      msg.textContent = t("连不上服务器，请检查网络");
    }
  };
}

let signedUpTimer = null;
function renderSignedUp() {
  let left = 5;
  app.innerHTML = `
  <div class="signin">
    <img class="logo" src="/icon-192.png" alt="">
    <div class="signed-up">
      <div class="check">✓</div>
      <h1>${t("注册成功！")}</h1>
      <p>${t("你的账号：")}<b>${esc(store.email)}</b></p>
      <p class="muted" id="su-count"></p>
      <button class="primary big" id="su-go">${t("立即登录")}</button>
    </div>
  </div>`;
  const go = () => { clearInterval(signedUpTimer); renderSignIn(); $("#si-password")?.focus(); };
  const tick = () => { $("#su-count").textContent = t("{} 秒后自动跳转到登录页面", left); if (left-- <= 0) go(); };
  clearInterval(signedUpTimer);
  signedUpTimer = setInterval(tick, 1000);
  tick();
  $("#su-go").onclick = go;
}

function signOut() {
  store.token = null;
  save("bp.token", null);
  save("bp.cache", null);
  Object.assign(store, { board: null, base: null, version: 0, dirty: false });
  ui.editing = null;
  ui.settingsTab = null;
  render();
}

// MARK: - Start

applyScale();
restoreCache();
if (store.board) normalize(store.board);
render();
sync();
if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
