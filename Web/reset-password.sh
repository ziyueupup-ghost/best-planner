#!/bin/zsh
# Set a new password for an account on the live site (for when someone forgets theirs).
# Also signs that account out everywhere and clears any login lock.
# Usage: ./reset-password.sh            (asks for the account and the new password)
set -euo pipefail
cd "${0:A:h}"
export PATH="$HOME/.local/node/bin:$PATH"

read "account?账号（邮箱或用户名）: "
account="${${account:l}// /}"
if [[ ! "$account" =~ '^[a-z0-9._@+-]{3,200}$' ]]; then
  echo "账号格式不对" >&2; exit 1
fi
read -s "pw1?新密码（至少 8 位）: "; echo
read -s "pw2?再输一次: "; echo
if [[ "$pw1" != "$pw2" ]]; then echo "两次输入不一样" >&2; exit 1; fi
if (( ${#pw1} < 8 )); then echo "密码至少 8 位" >&2; exit 1; fi

found=$(npx --yes wrangler@4 d1 execute best-planner --remote --json \
  --command "SELECT COUNT(*) AS n FROM users WHERE email = '$account'" 2>/dev/null \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s)[0].results[0].n)}catch{console.log("?")}})')
if [[ "$found" == "?" ]]; then echo "连不上数据库（先运行 npx wrangler@4 whoami 看看是否已登录 Cloudflare）" >&2; exit 1; fi
if [[ "$found" != "1" ]]; then echo "找不到账号 $account" >&2; exit 1; fi

# Same hashing as src/worker.js: PBKDF2-SHA256, 100 000 rounds, 16-byte salt, hex.
# The password goes to node through an environment variable, never on the command line.
salt_hash=$(NEW_PW="$pw1" node -e '
  const c = require("crypto"); const salt = c.randomBytes(16);
  const hash = c.pbkdf2Sync(process.env.NEW_PW, salt, 100000, 32, "sha256");
  console.log(salt.toString("hex") + " " + hash.toString("hex"));')
unset pw1 pw2
salt=${salt_hash% *}; hash=${salt_hash#* }

tmp=$(mktemp -t reset-password); sql="$tmp.sql"
trap 'rm -f "$tmp" "$sql"' EXIT
cat > "$sql" <<SQL
DELETE FROM sessions WHERE user_id IN (SELECT id FROM users WHERE email = '$account');
UPDATE users SET salt = '$salt', hash = '$hash', failed = 0, locked_until = 0 WHERE email = '$account';
SQL

out=$(npx --yes wrangler@4 d1 execute best-planner --remote --json --file "$sql" 2>&1) || { echo "$out" >&2; exit 1; }
echo "✓ 已重设 $account 的密码。所有设备需要用新密码重新登录。"
