# 設定ファイル (pipeline_config.conf) の使用方法

## 概要

`get_pipelines.sh` と `get_accounts.sh` では、Bash変数形式の設定ファイル `pipeline_config.conf` を使用してデフォルト設定を管理できます。

## 設定ファイルの作成

```bash
# 例ファイルをコピーして設定ファイルを作成
cp pipeline_config.example.conf pipeline_config.conf

# 設定ファイルを編集
vi pipeline_config.conf
```

## 設定項目

### AWS設定
- `AWS_DEFAULT_PROFILE`: デフォルトのAWSプロファイル名
- `AWS_REGION`: AWSリージョン
- `AWS_PIPELINES_PROFILE`: get_pipelines.sh で使用するAWSプロファイル
- `AWS_ACCOUNTS_PROFILE`: get_accounts.sh で使用するAWSプロファイル

### キャッシュ設定
- `CACHE_TTL`: キャッシュ有効期限（秒）
- `CACHE_ENABLED`: キャッシュを有効にするか (true/false)

### 表示設定
- `DISPLAY_FORMAT`: 出力形式 (table|json|csv)
- `DISPLAY_QUIET`: 静寂モード (true/false)
- `DISPLAY_PROGRESS_INTERVAL`: プログレス表示間隔

### パフォーマンス設定
- `PERFORMANCE_MAX_PARALLEL`: 並列処理数

### フィルタリング設定
- `PIPELINES_DEFAULT_QUERY`: デフォルトのJMESPathクエリフィルター
- `PIPELINES_DEFAULT_STATUS`: デフォルトのステータスフィルター (ALL|Succeeded|Failed|InProgress|Stopped)

## 設定例

### マルチアカウント環境での設定

```bash
# AWS設定
AWS_DEFAULT_PROFILE="default"
AWS_REGION="us-east-1"
AWS_PIPELINES_PROFILE="production-pipeline-account"
AWS_ACCOUNTS_PROFILE="organizations-management-account"

# キャッシュ設定
CACHE_TTL=3600  # 1時間キャッシュ

# パフォーマンス設定
PERFORMANCE_MAX_PARALLEL=20  # 並列処理数を増加

# フィルタリング設定
PIPELINES_DEFAULT_QUERY='pipelines[?ends_with(name, `customizations-pipeline`)]'  # customizationsパイプラインのみ
PIPELINES_DEFAULT_STATUS="ALL"  # 全ステータス
```

### 開発環境用設定

```bash
# AWS設定
AWS_DEFAULT_PROFILE="dev-profile"
AWS_REGION="ap-northeast-1"
AWS_PIPELINES_PROFILE="dev-pipeline-account"
AWS_ACCOUNTS_PROFILE="dev-organizations-account"

# キャッシュ設定
CACHE_TTL=600  # 10分キャッシュ（頻繁に変更される環境）

# 表示設定
DISPLAY_QUIET=true  # プログレス表示なし

# パフォーマンス設定
PERFORMANCE_MAX_PARALLEL=10  # 控えめな並列処理
```

## Bash変数形式の利点

1. **ネイティブサポート**: Bashの`source`コマンドで直接読み込める
2. **高速**: パース処理が不要で瞬時に読み込み
3. **シンプル**: 追加の依存関係やツールが不要
4. **デバッグしやすい**: 変数の値を直接確認できる
5. **環境変数との親和性**: 既存の環境変数と統合しやすい

## 優先順位

設定の優先順位は以下の通りです：

1. コマンドライン引数（最優先）
2. 設定ファイル（pipeline_config.conf）
3. デフォルト値

例：
```bash
# 設定ファイルでDISPLAY_FORMAT="json"でも、コマンドライン引数が優先される
./get_pipelines.sh -f table
```

## 設定ファイルの確認

設定ファイルが正しく読み込まれているかは、以下で確認できます：

```bash
# テストスクリプトで設定値を確認
./test_config.sh

# 設定ファイルの内容を直接確認
cat pipeline_config.conf
```

## 環境変数との組み合わせ

設定ファイルと環境変数を組み合わせることも可能です：

```bash
# 一時的に異なるプロファイルを使用
AWS_PIPELINES_PROFILE="temporary-profile" ./get_pipelines.sh

# 環境変数で設定を上書き
export AWS_PIPELINES_PROFILE="my-profile"
./get_pipelines.sh
```

## トラブルシューティング

### 設定ファイルが見つからない場合
```
⚠️  設定ファイルが見つかりません: pipeline_config.conf
💡 デフォルト設定を使用します。設定ファイルを作成する場合:
   cp pipeline_config.example.conf pipeline_config.conf
```

### 設定ファイルの構文エラー
```bash
# 設定ファイルの構文をチェック
bash -n pipeline_config.conf
```

### AWSプロファイルが見つからない場合
```bash
# 利用可能なプロファイルを確認
aws configure list-profiles

# プロファイルを設定
aws configure --profile your-profile-name
```

## セキュリティ注意事項

- 設定ファイルには機密情報（アクセスキーなど）を直接記載しないでください
- AWSプロファイル名のみを記載し、認証情報は`~/.aws/credentials`で管理してください
- 設定ファイルの権限を適切に設定してください（`chmod 600 pipeline_config.conf`）