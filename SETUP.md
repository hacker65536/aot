# AOT (AWS Operations Tools) セットアップガイド

## 初期設定

### 1. 設定ファイルの作成

```bash
# 設定ファイルのテンプレートをコピー
cp aot_config.example.conf aot_config.conf

# 設定ファイルを編集
vi aot_config.conf
```

### 2. AWS プロファイルの設定

`aot_config.conf` で以下の項目を環境に合わせて設定してください：

```bash
# get_pipelines.sh で使用するAWSプロファイル
AWS_PIPELINES_PROFILE="your-pipeline-account-profile"

# get_accounts.sh で使用するAWSプロファイル  
AWS_ACCOUNTS_PROFILE="your-organizations-management-profile"

# AWSリージョン
AWS_REGION="ap-northeast-1"
```

### 3. セキュリティ注意事項

- `aot_config.conf` は個人の設定ファイルです
- このファイルは `.gitignore` に含まれており、Gitで追跡されません
- AWSプロファイル名などの固有情報が含まれるため、共有しないでください
- 認証情報は `~/.aws/credentials` で管理し、設定ファイルには含めないでください

### 4. 設定の確認

```bash
# 設定ファイルの読み込みテスト
./test_config.sh

# スクリプトの動作確認
./get_pipelines.sh --help
./get_accounts.sh --help
```

## 設定例

### マルチアカウント環境

```bash
# AWS設定
AWS_PIPELINES_PROFILE="production-pipeline-account"
AWS_ACCOUNTS_PROFILE="organizations-management-account"
AWS_REGION="us-east-1"

# パフォーマンス設定
PERFORMANCE_MAX_PARALLEL=20
CACHE_TTL=3600  # 1時間キャッシュ

# フィルタリング設定
PIPELINES_DEFAULT_QUERY='pipelines[?ends_with(name, `customizations-pipeline`)]'
PIPELINES_DEFAULT_STATUS="ALL"
```

### 開発環境

```bash
# AWS設定
AWS_PIPELINES_PROFILE="dev-pipeline-account"
AWS_ACCOUNTS_PROFILE="dev-organizations-account"
AWS_REGION="ap-northeast-1"

# 開発用設定
PERFORMANCE_MAX_PARALLEL=10
CACHE_TTL=600  # 10分キャッシュ
DISPLAY_QUIET=true  # プログレス表示なし
```

## トラブルシューティング

### 設定ファイルが見つからない場合

```
⚠️  設定ファイルが見つかりません: aot_config.conf
💡 デフォルト設定を使用します。設定ファイルを作成する場合:
   cp aot_config.example.conf aot_config.conf
```

### AWSプロファイルエラーの場合

```bash
# 利用可能なプロファイルを確認
aws configure list-profiles

# プロファイルの認証情報を確認
aws sts get-caller-identity --profile your-profile-name
```