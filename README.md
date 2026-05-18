# colorful-servers

竹内貴紀が管理する VPS サーバー群の設定記録リポジトリ。

各サーバーは `*.colorful-servers.com` のドメインを持ち、ホスト名には和色（日本の伝統的な色名）を使っている。

## サーバー一覧

| ホスト名 | ドメイン | 概要 |
|---------|---------|------|
| sumi | sumi.colorful-servers.com | [→ sumi/README.md](./sumi/README.md) |

## このリポジトリについて

- 各ホスト名のディレクトリに、そのサーバーの設定・運用記録を Markdown で管理する
- 秘密情報は暗号化ツール（sops / age / git-crypt）で保護してからコミットする
- 詳細は [CLAUDE.md](./CLAUDE.md) を参照
