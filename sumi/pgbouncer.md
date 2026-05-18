# PgBouncer 1.25.1（Docker Compose）

`sumi.colorful-servers.com` 上で稼働する PgBouncer の設定記録。
PostgreSQL 17 と同じ `~/postgres/compose.yaml` で管理。

## 役割

Vercel（サーバーレス）からの接続プール管理。
サーバーレス環境は関数ごとに接続を作成・破棄するため、PostgreSQL の接続数上限に達しやすい。
PgBouncer の `transaction` モードで接続を使い回す。

```
Vercel → [TLS] → PgBouncer :6432 → PostgreSQL :5432（内部ネットワーク）
```

## ディレクトリ構成（VPS 上）

```
/home/pomme/postgres/
├── pgbouncer.ini           # PgBouncer 設定
├── userlist.txt            # pgbouncer ユーザーの認証情報（秘密情報 — コミット不可）
└── pgbouncer-certs/
    ├── server.crt          # Let's Encrypt 証明書（certbot デプロイフックで自動更新）
    └── server.key          # 対応する秘密鍵（秘密情報 — コミット不可）
```

## pgbouncer.ini

```ini
[databases]
timesheet = host=postgres port=5432 dbname=timesheet

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
auth_user = pgbouncer
auth_query = SELECT usename, passwd FROM pgbouncer.get_auth($1)
client_tls_sslmode = require
client_tls_cert_file = /etc/pgbouncer/certs/server.crt
client_tls_key_file = /etc/pgbouncer/certs/server.key
server_tls_sslmode = require
pool_mode = transaction
max_client_conn = 100
default_pool_size = 20
log_connections = 0
```

## 認証の仕組み

`auth_query` を使って PostgreSQL からクライアントのパスワードハッシュを動的に取得する方式。
`pg_authid` はスーパーユーザー専用のため、`SECURITY DEFINER` 関数を経由してアクセスする。

### timesheet DB に作成した関数

```sql
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
```

### userlist.txt

`pgbouncer` ユーザー（`auth_user`）の認証情報のみ記載。平文パスワードで記載する必要がある
（SCRAM はチャレンジ-レスポンス方式のため、PgBouncer がサーバーへ接続する際に平文パスワードが必要）。

```
"pgbouncer" "平文パスワード"
```

## SSL 証明書

Let's Encrypt 証明書（`db.sumi.colorful-servers.com`）を使用。
certbot デプロイフック（`/etc/letsencrypt/renewal-hooks/deploy/pgbouncer-cert.sh`）が自動更新時に `pgbouncer-certs/` にコピーし PgBouncer を再起動する。

証明書ファイルは `chmod 644` で edoburu/pgbouncer イメージのコンテナユーザーが読み取れるよう設定。

## ファイアウォール設定

### UFW ルール

```bash
ufw allow 6432/tcp              # PgBouncer ポートを開放
ufw route allow proto tcp to 10.0.1.2 port 6432  # Docker コンテナへの転送を許可
```

### UFW と Docker の注意点

Docker はコンテナのポートを `iptables` に直接追加するが、`DOCKER-USER` チェーン経由で `ufw-user-forward` が評価される。
`ufw route allow` で Docker コンテナへの転送を明示的に許可する必要がある。

`/etc/default/ufw` の `DEFAULT_FORWARD_POLICY="ACCEPT"` も設定済み。

## Vercel からの接続 URL

```
postgresql://timesheet_user:PASSWORD@db.sumi.colorful-servers.com:6432/timesheet?sslmode=require
```

パスワードは Vercel の環境変数（`DATABASE_URL`）で管理。
