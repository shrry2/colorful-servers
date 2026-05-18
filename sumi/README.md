# sumi (墨)

`sumi.colorful-servers.com` の設定記録。

## サーバー概要

| 項目 | 値 |
|------|------|
| OS | Ubuntu 24.04 |
| プラン | VPS 12GB（8GB + 無料4GB増設） |
| vCPU | 6コア |
| メモリ | 12GB |
| NVMe SSD | 400GB |
| 一般ユーザー | `pomme` |
| SSH ポート | 51482 |
| SSH エイリアス | `sumi`（ローカル `~/.ssh/config` に設定済み） |

## インストール済みソフトウェア

| ソフトウェア | バージョン |
|-------------|-----------|
| Docker Engine | 29.5.0 |
| Docker Compose | v5.1.3 |
| certbot | — |
| python3-certbot-dns-cloudflare | — |

`pomme` ユーザーは `docker` グループに追加済み（`sudo` なしで `docker` コマンドを実行可能）。

## 稼働中のサービス

| サービス | 状態 | 詳細 |
|---------|------|------|
| PostgreSQL 17 | 稼働中 | [→ postgres.md](./postgres.md) |
| PgBouncer 1.25.1 | 稼働中 | [→ pgbouncer.md](./pgbouncer.md) |

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-05-17 | リポジトリ初期化、記録開始 |
| 2026-05-18 | Let's Encrypt 証明書取得（`db.sumi.colorful-servers.com`）、PgBouncer 導入、Cloudflared 削除 |
