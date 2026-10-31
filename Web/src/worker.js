// Best Planner sync server. Each account has one board (the same JSON as planner.json).
// Clients save with the version they started from; if someone else saved meanwhile the
// save is refused (409) with the current board, the client merges and saves again.

const SESSION_DAYS = 180;
const MAX_BOARD_BYTES = 8 * 1024 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/api/")) return env.ASSETS.fetch(request);
    try {
      const route = `${request.method} ${url.pathname}`;
      switch (route) {
        case "POST /api/signup": return await signup(request, env);
        case "POST /api/login": return await login(request, env);
        case "POST /api/logout": return await logout(request, env);
        case "POST /api/password": return await changePassword(request, env);
        case "GET /api/board": return await getBoard(request, env, url);
        case "PUT /api/board": return await putBoard(request, env);
        default: return json({ error: "not_found" }, 404);
      }
    } catch (e) {
      if (e instanceof Response) return e;
      return json({ error: "server", message: String(e && e.message || e) }, 500);
    }
  },
};

// MARK: Accounts

async function signup(request, env) {
  const { email, password, invite } = await body(request);
  // Sign-ups need the invite code (a secret set with `wrangler secret put INVITE_CODE`).
  if (!env.INVITE_CODE || (invite || "").trim() !== env.INVITE_CODE) return json({ error: "invite" }, 403);
  const mail = normalizeEmail(email);
  if (!mail) return json({ error: "email" }, 400);
  if (typeof password !== "string" || password.length < 8) return json({ error: "password_short" }, 400);
  const exists = await env.DB.prepare("SELECT id FROM users WHERE email = ?").bind(mail).first();
  if (exists) return json({ error: "email_taken" }, 409);
  const id = crypto.randomUUID();
  const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
  const hash = await hashPassword(password, salt);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO users (id, email, salt, hash, created_at) VALUES (?, ?, ?, ?, ?)").bind(id, mail, salt, hash, Date.now()),
    env.DB.prepare("INSERT INTO boards (user_id, version, data, updated_at) VALUES (?, 0, NULL, ?)").bind(id, Date.now()),
  ]);
  return json({ token: await newSession(env, id), email: mail });
}

async function login(request, env) {
  const { email, password } = await body(request);
  const mail = normalizeEmail(email);
  const user = mail && await env.DB.prepare("SELECT * FROM users WHERE email = ?").bind(mail).first();
  if (!user) return json({ error: "wrong" }, 401);
  if (user.locked_until > Date.now()) return json({ error: "locked" }, 429);
  if (typeof password !== "string" || await hashPassword(password, user.salt) !== user.hash) {
    // Five wrong passwords in a row: wait 15 minutes.
    const failed = user.failed + 1;
    const lock = failed >= 5 ? Date.now() + 15 * 60_000 : 0;
    await env.DB.prepare("UPDATE users SET failed = ?, locked_until = ? WHERE id = ?").bind(lock ? 0 : failed, lock, user.id).run();
    return json({ error: "wrong" }, 401);
  }
  await env.DB.prepare("UPDATE users SET failed = 0, locked_until = 0 WHERE id = ?").bind(user.id).run();
  return json({ token: await newSession(env, user.id), email: mail });
}

async function logout(request, env) {
  const token = bearer(request);
  if (token) await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256(token)).run();
  return json({ ok: true });
}

async function changePassword(request, env) {
  const user = await authUser(request, env);
  const { oldPassword, newPassword } = await body(request);
  const row = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(user).first();
  if (await hashPassword(oldPassword || "", row.salt) !== row.hash) return json({ error: "wrong" }, 403);
  if (typeof newPassword !== "string" || newPassword.length < 8) return json({ error: "password_short" }, 400);
  const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
  await env.DB.prepare("UPDATE users SET salt = ?, hash = ? WHERE id = ?").bind(salt, await hashPassword(newPassword, salt), user).run();
  return json({ ok: true });
}

// MARK: Board

async function getBoard(request, env, url) {
  const user = await authUser(request, env);
  const row = await env.DB.prepare("SELECT version, data FROM boards WHERE user_id = ?").bind(user).first();
  const version = row ? row.version : 0;
  // The client already has this version: no need to send the whole board again.
  if (url.searchParams.get("known") === String(version)) return json({ version, unchanged: true });
  return json({ version, board: row && row.data ? JSON.parse(await gunzip(row.data)) : null });
}

async function putBoard(request, env) {
  const user = await authUser(request, env);
  const text = await request.text();
  if (text.length > MAX_BOARD_BYTES) return json({ error: "too_large" }, 413);
  const { baseVersion, board } = JSON.parse(text);
  if (!board || !Array.isArray(board.tasks) || !Array.isArray(board.columns)) return json({ error: "bad_board" }, 400);
  const data = await gzip(JSON.stringify(board));
  const result = await env.DB.prepare("UPDATE boards SET version = version + 1, data = ?, updated_at = ? WHERE user_id = ? AND version = ?")
    .bind(data, Date.now(), user, baseVersion).run();
  if (result.meta.changes === 1) return json({ version: baseVersion + 1 });
  // Saved elsewhere meanwhile: send the current board back for merging.
  const row = await env.DB.prepare("SELECT version, data FROM boards WHERE user_id = ?").bind(user).first();
  return json({ error: "conflict", version: row.version, board: row.data ? JSON.parse(await gunzip(row.data)) : null }, 409);
}

// MARK: Helpers

async function authUser(request, env) {
  const token = bearer(request);
  if (!token) throw json({ error: "auth" }, 401);
  const key = await sha256(token);
  const row = await env.DB.prepare("SELECT user_id, expires_at FROM sessions WHERE token_hash = ?").bind(key).first();
  if (!row || row.expires_at < Date.now()) throw json({ error: "auth" }, 401);
  // Sliding expiry: renew at most once a day.
  const renewed = Date.now() + SESSION_DAYS * 86_400_000;
  if (renewed - row.expires_at > 86_400_000) {
    await env.DB.prepare("UPDATE sessions SET expires_at = ? WHERE token_hash = ?").bind(renewed, key).run();
  }
  return row.user_id;
}

async function newSession(env, userID) {
  const token = base64url(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.prepare("INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)")
    .bind(await sha256(token), userID, Date.now() + SESSION_DAYS * 86_400_000).run();
  return token;
}

function bearer(request) {
  const h = request.headers.get("Authorization") || "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}

async function body(request) {
  try { return await request.json(); } catch { throw json({ error: "bad_request" }, 400); }
}

function normalizeEmail(email) {
  const e = typeof email === "string" ? email.trim().toLowerCase() : "";
  // An email address or a plain user name (3–32 letters, digits, . _ -).
  if (/^[a-z0-9][a-z0-9._-]{2,31}$/.test(e)) return e;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e) && e.length <= 200 ? e : null;
}

async function hashPassword(password, saltHex) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: unhex(saltHex), iterations: 100_000 }, key, 256);
  return hex(new Uint8Array(bits));
}

async function sha256(text) {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))));
}

async function gzip(text) {
  const stream = new Blob([text]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function gunzip(data) {
  const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data);
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  return await new Response(stream).text();
}

const hex = (bytes) => [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
const unhex = (s) => new Uint8Array(s.match(/../g).map((h) => parseInt(h, 16)));
const base64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
