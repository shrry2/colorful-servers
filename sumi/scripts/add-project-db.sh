#!/bin/bash
# VPS 上の ~/postgres/ ディレクトリで実行する
# 使い方: bash scripts/add-project-db.sh <project_name>
#
# 実行すると:
#   1. 本番・ステージング用のユーザーと DB を PostgreSQL に作成
#   2. PUBLIC の CONNECT 権限を剥奪し、正規ユーザーと pgbouncer にのみ付与
#   3. 両 DB に pgbouncer.get_auth() 関数を設置
#   4. pgbouncer.ini に DB エントリを追記
#   5. PgBouncer を再起動

set -euo pipefail

PROJECT="${1:-}"
if [[ -z "$PROJECT" ]]; then
  echo "使い方: $0 <project_name>" >&2
  exit 1
fi

PROD_DB="${PROJECT}"
STAGING_DB="${PROJECT}_staging"
PROD_USER="${PROJECT}_user"
STAGING_USER="${PROJECT}_staging_user"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PGBOUNCER_INI="${SCRIPT_DIR}/../pgbouncer.ini"

if [[ ! -f "$PGBOUNCER_INI" ]]; then
  echo "エラー: pgbouncer.ini が見つかりません: ${PGBOUNCER_INI}" >&2
  echo "~/postgres/ ディレクトリで実行しているか確認してください" >&2
  exit 1
fi

echo "=== DB 作成: ${PROJECT} ==="
echo "  本番        DB=${PROD_DB}    ユーザー=${PROD_USER}"
echo "  ステージング DB=${STAGING_DB} ユーザー=${STAGING_USER}"
echo ""

read -rsp "本番ユーザー (${PROD_USER}) のパスワード: " PROD_PASS; echo
read -rsp "ステージングユーザー (${STAGING_USER}) のパスワード: " STAGING_PASS; echo
echo ""

# ' を '' にエスケープ（SQL インジェクション対策）
PROD_PASS_ESC="${PROD_PASS//\'/\'\'}"
STAGING_PASS_ESC="${STAGING_PASS//\'/\'\'}"

PSQL="docker compose exec -T postgres psql -U postgres"

echo "--- ユーザー・DB 作成 ---"
$PSQL <<EOSQL
CREATE USER ${PROD_USER} WITH PASSWORD '${PROD_PASS_ESC}';
CREATE USER ${STAGING_USER} WITH PASSWORD '${STAGING_PASS_ESC}';
CREATE DATABASE ${PROD_DB} OWNER ${PROD_USER};
CREATE DATABASE ${STAGING_DB} OWNER ${STAGING_USER};
EOSQL

echo "--- CONNECT 権限を制限 ---"
$PSQL <<EOSQL
REVOKE CONNECT ON DATABASE ${PROD_DB} FROM PUBLIC;
REVOKE CONNECT ON DATABASE ${STAGING_DB} FROM PUBLIC;
GRANT CONNECT ON DATABASE ${PROD_DB} TO ${PROD_USER}, pgbouncer;
GRANT CONNECT ON DATABASE ${STAGING_DB} TO ${STAGING_USER}, pgbouncer;
EOSQL
echo "  OK"

echo "--- pgbouncer.get_auth() 関数を設置 ---"
for DB in "$PROD_DB" "$STAGING_DB"; do
  $PSQL -d "$DB" <<'EOSQL'
CREATE SCHEMA IF NOT EXISTS pgbouncer;

CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_username TEXT)
RETURNS TABLE(usename TEXT, passwd TEXT)
LANGUAGE SQL
SECURITY DEFINER AS $$
  SELECT rolname::TEXT, rolpassword::TEXT
  FROM pg_catalog.pg_authid
  WHERE rolcanlogin
    AND rolname = p_username;
$$;

REVOKE ALL ON FUNCTION pgbouncer.get_auth(TEXT) FROM PUBLIC;
GRANT USAGE ON SCHEMA pgbouncer TO pgbouncer;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(TEXT) TO pgbouncer;
EOSQL
  echo "  ${DB}: OK"
done

echo "--- pgbouncer.ini を更新 ---"
if grep -qE "^${PROD_DB}[[:space:]]*=" "$PGBOUNCER_INI"; then
  echo "  ${PROD_DB}: すでに存在します（スキップ）"
else
  sed -i "/^\[pgbouncer\]/i ${PROD_DB} = host=postgres port=5432 dbname=${PROD_DB}" "$PGBOUNCER_INI"
  sed -i "/^\[pgbouncer\]/i ${STAGING_DB} = host=postgres port=5432 dbname=${STAGING_DB}" "$PGBOUNCER_INI"
  echo "  ${PROD_DB}, ${STAGING_DB}: 追記しました"
fi

echo "--- PgBouncer を再起動 ---"
docker compose restart pgbouncer

echo ""
echo "完了!"
echo ""
echo "接続 URL（パスワードは別途管理）:"
echo "  本番:         postgresql://${PROD_USER}:PASSWORD@db.sumi.colorful-servers.com:6432/${PROD_DB}?sslmode=require"
echo "  ステージング: postgresql://${STAGING_USER}:PASSWORD@db.sumi.colorful-servers.com:6432/${STAGING_DB}?sslmode=require"
