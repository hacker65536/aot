# 設定ファイル (pipeline_config.ini) の使用方法

## 概要

`get_pipelines.sh` では、INI形式の設定ファイル `pipeline_config.ini` を使用してデフォルト設定を管理できます。

## 設定ファイルの作成

```bash
# 例ファイルをコピーして設定ファイルを作成
cp pipeline_config.example.ini pipeline_config.ini

# 設定ファイルを編集
vi pipeline_config.ini
```

## 設定項目

### [aws] セクション
- `default_profile`: デフォルトのAWSプロファイル名（デフォルト: default）
- `region`: AWSリージョン（デフォルト: 空文字）

### [aws.pipelines] セクション
- `profile`: get_pipelines.sh で使用するAWSプロファイル名

### [aws.accounts] セクション  
- `profile`: get_accounts.sh で使用するAWSプロファイル名（通常はOrganizations管理アカウント）

### [cache] セクション
- `ttl`: キャッシュ有効期限（秒）（デフォルト: 1800 = 30分）
- `enabled`: キャッシュを有効にするか（デフォルト: true）

### [display] セクション
- `format`: 出力形式 table|json|csv（デフォルト: table）
- `quiet`: 静寂モード（デフォルト: false）
- `progress_interval`: プログレス表示間隔（デフォルト: 25）

### [performance] セクション
- `max_parallel`: 並列処理数（デフォルト: 15）

## 設定例

### マルチアカウント環境での設定例

```ini
[aws]
default_profile = default
region = us-east-1

[aws.pipelines]
# CodePipelineがあるアカウントのプロファイル
profile = production-account-profile

[aws.accounts]
# AWS Organizations管理アカウントのプロファイル
profile = organizations-management-profile

[cache]
ttl = 3600  # 1時間キャッシュ

[performance]
max_parallel = 20  # 並列処理数を増加
```

### 開発環境用設定

```ini
[aws]
default_profile = dev-profile
region = ap-northeast-1

[aws.pipelines]
# 開発環境のCodePipelineアカウント
profile = dev-pipeline-profile

[aws.accounts]
# 開発環境のOrganizations管理アカウント
profile = dev-organizations-profile

[cache]
ttl = 600  # 10分キャッシュ（頻繁に変更される環境）

[display]
quiet = true  # プログレス表示なし

[performance]
max_parallel = 10  # 控えめな並列処理
```

## 優先順位

設定の優先順位は以下の通りです：

1. コマンドライン引数（最優先）
2. 設定ファイル（pipeline_config.ini）
3. デフォルト値

例：
```bash
# 設定ファイルでformat=jsonでも、コマンドライン引数が優先される
./get_pipelines.sh -f table
```

## 設定ファイルの確認

設定ファイルが正しく読み込まれているかは、以下で確認できます：

```bash
# テストスクリプトで設定値を確認
./test_config.sh

# ヘルプで設定ファイルの場所を確認
./get_pipelines.sh --help
```

## トラブルシューティング

### 設定ファイルが見つからない場合
```
⚠️  設定ファイルが見つかりません: pipeline_config.ini
💡 デフォルト設定を使用します。設定ファイルを作成する場合:
   cp pipeline_config.example.ini pipeline_config.ini
```

### AWSプロファイルが見つからない場合
```bash
# 利用可能なプロファイルを確認
aws configure list-profiles

# プロファイルを設定
aws configure --profile your-profile-name
```

### 権限エラーの場合
```bash
# AWSプロファイルの認証情報を確認
aws sts get-caller-identity --profile your-profile-name
```