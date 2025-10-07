# AWS Organizations アカウントリスト取得ツール

`aws_cache.sh` を活用してAWS Organizationsのアカウント情報を効率的に取得・表示するスクリプトです。

## 特徴

🚀 **高速化**
- `aws_cache.sh` によるAPIレスポンスキャッシュ
- 初回実行後は高速にデータ取得

📊 **データ処理**
- 有効なアカウントのみフィルタリング
- Join日付による昇順ソート
- 複数の出力形式をサポート

⚙️ **柔軟な設定**
- キャッシュ有効期限の調整
- ステータスフィルター
- デバッグモード

## 前提条件

```bash
# 必要なファイル
./aws_cache.sh      # キャッシュ機能
./get_accounts.sh   # アカウントリスト取得

# 必要なツール
aws                 # AWS CLI
jq                  # JSON処理
```

## 使用方法

### 基本的な使用

```bash
# 有効なアカウントをテーブル形式で表示（30分キャッシュ）
./get_accounts.sh

# 初回実行時の動作
# 🔍 AWS Organizations からアカウントリストを取得中（キャッシュ利用）...
# 🔄 AWS APIを実行: aws organizations list-accounts --output json
# 💾 レスポンスをキャッシュに保存: ./aws_cache/abc123.json

# 2回目実行時の動作（キャッシュから高速取得）
# 🔍 AWS Organizations からアカウントリストを取得中（キャッシュ利用）...
# 📦 キャッシュから取得: aws organizations list-accounts --output json
```

### 出力形式の選択

```bash
# テーブル形式（デフォルト）
./get_accounts.sh -f table

# JSON形式
./get_accounts.sh -f json

# CSV形式
./get_accounts.sh -f csv
```

### ステータスフィルター

```bash
# 有効なアカウントのみ（デフォルト）
./get_accounts.sh -s ACTIVE

# 停止中のアカウントのみ
./get_accounts.sh -s SUSPENDED

# 全ステータス
./get_accounts.sh -s ALL
```

### キャッシュ制御

```bash
# キャッシュ有効期限を1時間に設定
./get_accounts.sh -c 3600

# デバッグモード（キャッシュの動作を確認）
./get_accounts.sh -d

# 強制的にキャッシュを更新
./aws_cache.sh -f -- aws organizations list-accounts
```

## 出力例

### テーブル形式

```
📊 AWS Organizations アカウント一覧
================================================================================================================
Account ID      Status       Name                           Email                Joined Date         
================================================================================================================
123456789012    ACTIVE       Production Account             prod@company.com     2023/01/15 10:30:25
234567890123    ACTIVE       Development Account            dev@company.com      2023/02/20 14:45:10
345678901234    ACTIVE       Staging Account                stage@company.com    2023/03/10 16:20:45
================================================================================================================
📈 統計: 総数=3, 有効=3, 停止=0
```

### JSON形式

```json
[
  {
    "Id": "123456789012",
    "Arn": "arn:aws:organizations::123456789012:account/o-example/123456789012",
    "Email": "prod@company.com",
    "Name": "Production Account",
    "Status": "ACTIVE",
    "JoinedMethod": "INVITED",
    "JoinedTimestamp": "2023-01-15T10:30:25.000Z"
  }
]
```

### CSV形式

```csv
AccountId,Status,Name,Email,JoinedDate
123456789012,ACTIVE,Production Account,prod@company.com,2023/01/15 10:30:25
234567890123,ACTIVE,Development Account,dev@company.com,2023/02/20 14:45:10
```

## 実用的な使用例

### 1. CSVファイルとして保存

```bash
./get_accounts.sh -f csv > accounts_$(date +%Y%m%d).csv
```

### 2. 特定の情報のみ抽出

```bash
# アカウントIDと名前のみ
./get_accounts.sh -f json | jq '.[] | {id: .Id, name: .Name}'

# 最近参加したアカウント（上位5件）
./get_accounts.sh -f json | jq '.[-5:]'
```

### 3. 他のツールとの連携

```bash
# 各アカウントのEC2インスタンス数を取得
./get_accounts.sh -f json | jq -r '.[].Id' | while read account_id; do
    echo "Account: $account_id"
    aws sts assume-role --role-arn "arn:aws:iam::$account_id:role/OrganizationAccountAccessRole" \
                        --role-session-name "check-instances" \
                        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
                        --output text | while read key secret token; do
        AWS_ACCESS_KEY_ID="$key" AWS_SECRET_ACCESS_KEY="$secret" AWS_SESSION_TOKEN="$token" \
        aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output text | wc -w
    done
done
```

## キャッシュの管理

```bash
# キャッシュ一覧を確認
./aws_cache.sh --list

# 特定のキャッシュをクリア
./aws_cache.sh --clear organizations

# 全キャッシュをクリア
./aws_cache.sh --clear
```

## トラブルシューティング

### よくある問題

1. **Organizations APIへのアクセス権限がない**
   ```
   ❌ エラー: AWS CLIコマンドエラー
   ```
   → Organizations の管理者権限が必要です

2. **aws_cache.sh が見つからない**
   ```
   ❌ エラー: aws_cache.sh が見つかりません
   ```
   → 同じディレクトリに `aws_cache.sh` を配置してください

3. **jq が見つからない**
   ```bash
   # jqをインストール
   brew install jq  # macOS
   apt-get install jq  # Ubuntu/Debian
   ```

### デバッグ方法

```bash
# デバッグモードで実行
./get_accounts.sh -d

# AWS CLIを直接実行して確認
aws organizations list-accounts

# キャッシュの状態を確認
./aws_cache.sh --list
```

## パフォーマンス

- **初回実行**: ~2-5秒（AWS API呼び出し）
- **キャッシュ利用時**: ~0.1-0.5秒（ローカルファイル読み込み）
- **推奨キャッシュ期間**: 30分-1時間（アカウント情報は頻繁に変更されないため）