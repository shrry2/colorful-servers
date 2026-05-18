# PostgreSQL 17（Docker Compose）

`sumi.colorful-servers.com` 上で稼働する PostgreSQL 17 の設定記録。

## ディレクトリ構成（VPS 上）

```
/home/pomme/postgres/
├── compose.yaml
├── .env                    # POSTGRES_PASSWORD を定義（秘密情報 — コミット不可）
├── pgbouncer.ini           # PgBouncer 設定（→ pgbouncer.md）
├── userlist.txt            # PgBouncer 認証用（秘密情報 — コミット不可）
├── certs/
│   ├── server.crt          # Let's Encrypt 証明書（certbot デプロイフックで自動更新）
│   └── server.key          # 対応する秘密鍵（秘密情報 — コミット不可）
└── pgbouncer-certs/
    ├── server.crt          # PgBouncer 用 Let's Encrypt 証明書（同上）
    └── server.key          # 対応する秘密鍵（秘密情報 — コミット不可）
```

## compose.yaml

```yaml
services:
  postgres:
    image: postgres:17
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"   # 外部非公開（localhost のみ）
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./certs/server.crt:/var/lib/postgresql/server.crt:ro
      - ./certs/server.key:/var/lib/postgresql/server.key:ro
    command: >
      postgres
        -c ssl=on
        -c ssl_cert_file=/var/lib/postgresql/server.crt
        -c ssl_key_file=/var/lib/postgresql/server.key
    restart: unless-stopped

  pgbouncer:
    image: edoburu/pgbouncer:latest
    depends_on:
      - postgres
    ports:
      - "6432:6432"
    volumes:
      - ./pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro
      - ./userlist.txt:/etc/pgbouncer/userlist.txt:ro
      - ./pgbouncer-certs:/etc/pgbouncer/certs:ro
    restart: unless-stopped

volumes:
  postgres_data:
```

## データベース情報

| DB 名 | ユーザー名 | 用途 |
|-------|-----------|------|
| `timesheet` | `timesheet_user` | michica-inc/timesheet 本番 |
| `timesheet_staging` | `timesheet_staging_user` | michica-inc/timesheet ステージング |
| `fortune` | `fortune_user` | michica-inc/fortune 本番 |
| `fortune_staging` | `fortune_staging_user` | michica-inc/fortune ステージング |

- ポート: 5432（127.0.0.1 のみ。外部非公開）
- SSL: 有効（`SHOW ssl;` → `on`）
- パスワードは各プロジェクトの Vercel 環境変数で管理。リポジトリには保存しない。

## 新規プロジェクト DB の追加

`scripts/add-project-db.sh` で自動化済み。VPS 上の `~/postgres/` で実行する。

```bash
bash scripts/add-project-db.sh <project_name>
```

実行内容：
1. 本番・ステージング用ユーザーと DB を作成（`<project>_user` / `<project>_staging_user`）
2. 両 DB に `pgbouncer.get_auth()` 関数を設置（PgBouncer の `auth_query` に必要）
3. `pgbouncer.ini` に DB エントリを追記
4. PgBouncer を再起動

## 起動・停止コマンド（VPS で実行）

```bash
cd ~/postgres

docker compose up -d           # 全サービス起動
docker compose up -d pgbouncer # PgBouncer のみ起動
docker compose down            # 停止
docker compose ps              # 状態確認
docker compose logs -f         # ログ確認
docker compose restart postgres # PostgreSQL のみ再起動
```

## SSL 証明書

Let's Encrypt 証明書（`db.sumi.colorful-servers.com`）を PostgreSQL のサーバー証明書として使用。

| 項目 | 値 |
|------|------|
| ドメイン | `db.sumi.colorful-servers.com` |
| 発行元 | Let's Encrypt |
| 取得方法 | certbot + Cloudflare DNS プラグイン（DNS-01 チャレンジ） |
| 自動更新 | certbot のデプロイフック（`/etc/letsencrypt/renewal-hooks/deploy/pgbouncer-cert.sh`）で証明書をコピーし、postgres・pgbouncer を再起動 |

証明書ファイルは `chown 999:999 chmod 600` で PostgreSQL コンテナユーザー（UID 999）が読み取れるよう設定。

## ローカルから SSH トンネル経由で接続

マイグレーション実行やデータ確認など、ローカル Mac から直接 DB に接続する場合：

```bash
# SSH トンネルを張る（ローカルの 15432 → VPS の 5432）
ssh -L 15432:localhost:5432 sumi -N

# 別ターミナルでマイグレーション実行
DATABASE_URL="postgresql://timesheet_user:PASSWORD@127.0.0.1:15432/timesheet" \
  npx drizzle-kit migrate
```

> **注意:** `pnpm db:migrate` ではなく `npx drizzle-kit migrate` を直接使う理由:
> `pnpm db:migrate` は `NODE_ENV=development` を強制し dotenvx が `.env.development` を読み込むため、CLI で渡した `DATABASE_URL` が上書きされてしまう。
