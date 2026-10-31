// Three-way merge of boards, the same rules as the Mac app (Shared/Merge.swift):
// apply what this device changed since `base` on top of `theirs` (the server's board).
// When both sides changed the same field, this device wins.

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const pick = (b, m, t) => (same(m, b) ? t : m);

/** Ids (tags, flags, contacts): keep theirs, add what mine added, drop what mine removed. */
function mergeIDs(base = [], mine = [], theirs = []) {
  const removed = new Set(base.filter((id) => !mine.includes(id)));
  const result = theirs.filter((id) => !removed.has(id));
  for (const id of mine) if (!base.includes(id) && !result.includes(id)) result.push(id);
  return result;
}

/** Field by field. */
function mergeFields(b = {}, m = {}, t = {}) {
  const r = { ...t };
  for (const k of new Set([...Object.keys(b), ...Object.keys(m), ...Object.keys(t)])) {
    const v = pick(b[k], m[k], t[k]);
    if (v === undefined) delete r[k]; else r[k] = v;
  }
  return r;
}

/** Lists of items with ids (subtasks, dates, links, contacts). */
function mergeList(base = [], mine = [], theirs = [], mergeItem = mergeFields) {
  const baseByID = new Map(base.map((x) => [x.id, x]));
  const mineIDs = new Set(mine.map((x) => x.id));
  let result = theirs.filter((x) => !(baseByID.has(x.id) && !mineIDs.has(x.id)));
  for (const m of mine) {
    const b = baseByID.get(m.id);
    const i = result.findIndex((x) => x.id === m.id);
    if (b) {
      if (i >= 0) result[i] = mergeItem(b, m, result[i]);
      else if (!same(m, b)) result.push(m);
    } else if (i < 0) {
      result.push(m);
    }
  }
  const shared = mine.map((x) => x.id).filter((id) => baseByID.has(id));
  const baseOrder = base.map((x) => x.id).filter((id) => mineIDs.has(id));
  if (!same(shared, baseOrder) || mine.some((x) => !baseByID.has(x.id))) {
    const pos = new Map(mine.map((x, i) => [x.id, i]));
    result = result
      .map((x, i) => [x, i])
      .sort(([a, ai], [b, bi]) => {
        const pa = pos.get(a.id), pb = pos.get(b.id);
        if (pa !== undefined && pb !== undefined) return pa - pb;
        if (pa !== undefined) return -1;
        if (pb !== undefined) return 1;
        return ai - bi;
      })
      .map(([x]) => x);
  }
  return result;
}

function mergeTask(b, m, t) {
  const r = mergeFields(b, m, t);
  for (const k of ["tagIDs", "flagIDs", "contactIDs"]) r[k] = mergeIDs(b[k], m[k], t[k]);
  for (const k of ["subtasks", "dates", "autoMoves", "links"]) r[k] = mergeList(b[k], m[k], t[k]);
  const theirHistory = new Set((t.history || []).map((h) => h.id));
  r.history = [...(t.history || []), ...(m.history || []).filter((h) => !theirHistory.has(h.id))]
    .sort((x, y) => (x.date < y.date ? -1 : x.date > y.date ? 1 : 0));
  const theirSessions = new Set((t.focusSessions || []).map((s) => s.id));
  r.focusSessions = [...(t.focusSessions || []), ...(m.focusSessions || []).filter((s) => !theirSessions.has(s.id))];
  r.recurrenceSpawned = !!(m.recurrenceSpawned || t.recurrenceSpawned);
  r.updatedAt = (m.updatedAt || "") > (t.updatedAt || "") ? m.updatedAt : t.updatedAt;
  return r;
}

function mergeTasks(base = [], mine = [], theirs = []) {
  const b = new Map(base.map((x) => [x.id, x]));
  const m = new Map(mine.map((x) => [x.id, x]));
  const t = new Map(theirs.map((x) => [x.id, x]));
  const out = [];
  for (const task of theirs) {
    const bt = b.get(task.id), mt = m.get(task.id);
    if (bt && mt) out.push(same(mt, bt) ? task : mergeTask(bt, mt, task));
    else if (bt && !mt) continue;            // deleted here
    else if (!bt && mt) out.push(mt);        // added on both sides
    else out.push(task);                     // added elsewhere
  }
  for (const task of mine) {
    if (t.has(task.id)) continue;
    const bt = b.get(task.id);
    if (!bt || !same(task, bt)) out.push(task); // added here, or edited here but deleted elsewhere
  }
  return out;
}

export function mergeBoards(base, mine, theirs) {
  const r = { ...theirs };
  const settings = ["columns", "tags", "sortMode", "expandedGroups", "priorities", "defaultPriorityID",
    "subtaskPacks", "flags", "widgetColumnIDs", "widgetTagIDs"];
  for (const k of settings) {
    const v = pick(base[k], mine[k], theirs[k]);
    if (v !== undefined) r[k] = v;
  }
  r.contacts = mergeList(base.contacts, mine.contacts, theirs.contacts);
  const notes = { ...(theirs.dayNotes || {}) };
  const bn = base.dayNotes || {}, mn = mine.dayNotes || {};
  for (const k of new Set([...Object.keys(bn), ...Object.keys(mn)])) {
    if (bn[k] !== mn[k]) { if (mn[k] === undefined) delete notes[k]; else notes[k] = mn[k]; }
  }
  r.dayNotes = notes;
  r.tasks = mergeTasks(base.tasks, mine.tasks, theirs.tasks);
  const live = new Set(r.tasks.map((x) => x.id));
  r.trash = mergeTasks(base.trash, mine.trash, theirs.trash).filter((x) => !live.has(x.id));
  return r;
}

export { same };
