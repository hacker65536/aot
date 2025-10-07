# AFT Operations Toolkit

> 🚀 **aft-ops-toolkit** - AWS Control Tower Account Factory for Terraform (AFT) 環境の運用を効率化するためのスクリプトツールキットです。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![AWS](https://img.shields.io/badge/AWS-AFT-orange.svg)](https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html)

## ✨ 特徴

- 🎯 **AFT特化**: AFT環境の運用に最適化された専用ツール
- ⚡ **高速化**: インテリジェントキャッシュによる大幅な処理時間短縮
- 🔍 **高度検索**: JMESPathクエリによる柔軟なフィルタリング
- 📊 **可視化**: 直感的なテーブル・JSON・CSV出力
- 🛠️ **運用支援**: パフォーマンス分析・最適化機能
- 📚 **充実ドキュメント**: 詳細な使用例とベストプラクティス

## 🚀 主要機能

### 🔄 Pipeline Operations
- **`get_pipelines.sh`** - CodePipelineの監視・管理・分析
- 状態監視、フィルタリング、パフォーマンス分析

### 👥 Account Management
- **`get_accounts.sh`** - AWSアカウントの一覧・管理
- 組織構造の可視化、ステータス確認

### ⚡ Performance Optimization  
- **`aws_cache.sh`** - AWS API結果の高速キャッシュシステム
- TTL管理、キャッシュ分析、自動最適化

## 📚 詳細ドキュメント

すべての詳細ドキュメントは [`docs/`](docs/) ディレクトリに整理されています：

- **[docs/README.md](docs/README.md)** - 📖 ドキュメント一覧とナビゲーション
- **[docs/README_pipelines.md](docs/README_pipelines.md)** - 🔄 パイプライン管理の詳細
- **[docs/README_accounts.md](docs/README_accounts.md)** - 👥 アカウント管理の詳細
- **[docs/query_filter_feature.md](docs/query_filter_feature.md)** - 🔍 高度なフィルタリング機能
- **[docs/project_structure.md](docs/project_structure.md)** - 📁 プロジェクト構造の詳細

## ⚡ クイックスタート

### 基本的な使用方法
```bash
# パイプライン一覧を表示
./get_pipelines.sh

# アカウント一覧を表示
./get_accounts.sh
```

### 運用監視
```bash
# 失敗したパイプラインのみ表示
./get_pipelines.sh -s Failed

# customizationsパイプラインの状態確認
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]'

# JSON形式でデータ出力（他システム連携用）
./get_pipelines.sh -f json
```

### パフォーマンス分析
```bash
# キャッシュ効率を分析
./get_pipelines.sh --analyze-cache

# 特定リージョンのパフォーマンス確認
./get_pipelines.sh -r us-east-1 --analyze-cache
```

---

# AWS CLI Cache System

以下は、基盤となるキャッシュシステムの詳細です。

## 特徴

- 🚀 AWS CLIコマンドの実行結果を自動キャッシュ
- ⏰ TTL（Time To Live）によるキャッシュ有効期限管理
- 💾 JSONファイルによるローカルストレージ
- 🔄 強制更新オプション
- 📋 キャッシュ管理機能（一覧表示・削除）

## インストール

```bash
# スクリプトをダウンロード
curl -O https://raw.githubusercontent.com/your-repo/aws_cache.sh
chmod +x aws_cache.sh

# または直接クローン
git clone https://github.com/your-repo/aws-cli-cache.git
cd aws-cli-cache
```

## 使用方法

### 基本的な使用方法

```bash
# EC2インスタンス一覧を取得
./aws_cache.sh -- aws ec2 describe-instances

# S3バケット一覧を取得（10分キャッシュ）
./aws_cache.sh -t 600 -- aws s3api list-buckets

# 強制的にキャッシュを更新
./aws_cache.sh -f -- aws iam list-users

# デバッグモードで実行
./aws_cache.sh -d -- aws ec2 describe-instances

# キャッシュの存在と有効性をテスト
./aws_cache.sh --test "aws s3api list-buckets"
```

### オプション

| オプション | 説明 | 例 |
|-----------|------|-----|
| `-t, --ttl SECONDS` | キャッシュの有効期限（秒） | `-t 3600` |
| `-f, --force` | 強制的にキャッシュを更新 | `-f` |
| `-d, --debug` | デバッグモード（詳細ログを表示） | `-d` |
| `-l, --list` | キャッシュ一覧を表示 | `--list` |
| `-c, --clear [PATTERN]` | キャッシュをクリア | `--clear ec2` |
| `--test COMMAND` | 指定コマンドのキャッシュ存在・有効性をテスト | `--test "aws s3api list-buckets"` |
| `-h, --help` | ヘルプを表示 | `--help` |

### 環境変数

```bash
# キャッシュディレクトリを変更
export AWS_CACHE_DIR="/tmp/aws_cache"

# デフォルトTTLを変更（秒）
export AWS_CACHE_TTL=7200  # 2時間
```

## 使用例

### 1. 基本的なキャッシュ

```bash
# 通常実行（ログなし）
./aws_cache.sh -- aws ec2 describe-instances
# レスポンスJSONのみ出力

# デバッグモードで実行（詳細ログ表示）
./aws_cache.sh -d -- aws ec2 describe-instances
# 🔄 AWS APIを実行: aws ec2 describe-instances --output json
# 💾 レスポンスをキャッシュに保存: ./aws_cache/abc123.json

# 2回目実行（キャッシュから取得）
./aws_cache.sh -d -- aws ec2 describe-instances
# 📦 キャッシュから取得: aws ec2 describe-instances --output json
```

### 2. TTL指定

```bash
# 5分間キャッシュ
./aws_cache.sh -t 300 -- aws s3api list-buckets

# 1時間キャッシュ
./aws_cache.sh -t 3600 -- aws iam list-roles
```

### 3. キャッシュ管理

```bash
# キャッシュ一覧表示
./aws_cache.sh --list
# 📋 キャッシュ一覧:
#   abc123.json: aws ec2 describe-instances --output json (有効)
#   def456.json: aws s3api list-buckets --output json (期限切れ)

# 特定コマンドのキャッシュ存在・有効性をテスト（簡潔モード）
./aws_cache.sh --test "aws s3api list-buckets"
# 出力なし、終了コード 0=有効, 1=無効

# 詳細モード（デバッグ付き）
./aws_cache.sh --test "aws s3api list-buckets" -d
# 🔍 キャッシュテスト結果
# ================================================
# ✅ キャッシュ: 存在します
# 📅 作成日時: 2024/01/15 14:30:25
# ✅ TTL状態: 有効（残り45分30秒）

# 特定TTLでのキャッシュ有効性テスト
./aws_cache.sh --test "aws s3api list-buckets" -t 300

# 特定パターンのキャッシュを削除
./aws_cache.sh --clear ec2

# 全キャッシュを削除
./aws_cache.sh --clear
```

### 4. キャッシュテスト機能

```bash
# 基本的なキャッシュテスト（簡潔モード）
./aws_cache.sh --test "aws s3api list-buckets"
# 出力なし、終了コード 0=有効, 1=無効

# 詳細モード（デバッグ付き）
./aws_cache.sh --test "aws s3api list-buckets" -d
# 🔍 キャッシュテスト結果
# ================================================
# ✅ キャッシュ: 存在します
# 📅 作成日時: 2024/01/15 14:30:25
# ✅ TTL状態: 有効（残り45分30秒）

# 条件分岐での活用
if ./aws_cache.sh --test "aws s3api list-buckets" -t 300; then
    echo "✅ キャッシュ有効"
else
    echo "❌ キャッシュ更新が必要"
    ./aws_cache.sh -f -- aws s3api list-buckets
fi

# スクリプトでの自動化例
COMMAND="aws s3api list-buckets"
TTL=300  # 5分

# キャッシュ有効性をチェック（出力を抑制）
if ./aws_cache.sh --test "$COMMAND" -t $TTL >/dev/null 2>&1; then
    # キャッシュが有効な場合はそのまま使用
    ./aws_cache.sh -- $COMMAND
else
    # キャッシュが無効な場合は強制更新
    ./aws_cache.sh -f -- $COMMAND
fi
```

### 5. パイプライン処理

```bash
# jqと組み合わせてインスタンス名を取得
./aws_cache.sh -- aws ec2 describe-instances | \
  jq -r '.Reservations[].Instances[].Tags[]? | select(.Key=="Name") | .Value'

# 結果をファイルに保存
./aws_cache.sh -- aws s3api list-buckets > buckets.json
```

## ファイル構造

```
aws_cache/
├── abc123def.json  # キャッシュファイル（MD5ハッシュ名）
├── 456789ghi.json
└── ...
```

### キャッシュファイル形式

```json
{
  "command": ["aws", "ec2", "describe-instances", "--output", "json"],
  "response": { ... },  // AWS APIレスポンス
  "timestamp": "2024-01-01T12:00:00+09:00",
  "ttl": 3600
}
```

## 依存関係

- bash 4.0+
- AWS CLI v1/v2
- jq（JSONパース用）
- md5 または md5sum（キャッシュキー生成用）

## トラブルシューティング

### よくある問題

1. **AWS CLIが見つからない**
   ```bash
   # AWS CLIをインストール
   brew install awscli  # macOS
   # または
   pip install awscli
   ```

2. **jqが見つからない**
   ```bash
   # jqをインストール
   brew install jq  # macOS
   # または
   apt-get install jq  # Ubuntu/Debian
   ```

3. **権限エラー**
   ```bash
   # スクリプトに実行権限を付与
   chmod +x aws_cache.sh
   ```

## ライセンス

MIT License