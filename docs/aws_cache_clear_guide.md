# AWS Cache --clear オプション 詳細ガイド

## 🗑️ 基本的な使用方法

### 構文

```bash
./aws_cache.sh --clear [PATTERN]
```

### オプション

- **パターンなし**: 全キャッシュを削除
- **パターンあり**: 指定パターンにマッチするキャッシュのみ削除

## 📋 パターンマッチングの仕組み

### 内部実装（改善版）

```bash
# コマンド内容でマッチング（推奨）
for cache_file in "$CACHE_DIR"/*.json; do
    command_str=$(jq -r '.command | join(" ")' "$cache_file")
    if [[ "$command_str" == *"$pattern"* ]]; then
        rm -f "$cache_file"
    fi
done

# MD5ハッシュでマッチング（従来方式）
find "$CACHE_DIR" -name "*${pattern}*.json" -type f -delete
```

### マッチング方式

- **コマンド内容マッチング**: キャッシュファイル内のコマンド文字列で検索（推奨）
- **ファイル名マッチング**: MD5 ハッシュファイル名で検索（32 文字の 16 進数の場合のみ）
- **部分一致**: パターンがコマンド内容に含まれていれば対象
- **大文字小文字**: 区別される

## 🎯 実用的な使用例

### 1. サービス別削除

#### CodePipeline 関連のキャッシュを削除

```bash
./aws_cache.sh --clear codepipeline
```

**マッチするファイル例:**

```
✅ aws codepipeline list-pipelines --output json
✅ aws codepipeline get-pipeline-state --name pipeline-name --output json
❌ aws s3api list-buckets --output json
❌ aws ec2 describe-instances --output json
```

**実際の削除例:**

```bash
$ ./aws_cache.sh --clear codepipeline -d
🗑️  削除: abc123.json (コマンド: aws codepipeline list-pipelines --output json)
🗑️  削除: def456.json (コマンド: aws codepipeline get-pipeline-state --name my-pipeline --output json)
✅ 179 個のキャッシュファイルを削除しました
```

#### S3 関連のキャッシュを削除

```bash
./aws_cache.sh --clear s3
```

**マッチするファイル例:**

```
✅ aws s3api list-buckets
✅ aws s3api get-bucket-location
✅ aws s3 ls
❌ aws ec2 describe-instances
❌ aws iam list-users
```

#### EC2 関連のキャッシュを削除

```bash
./aws_cache.sh --clear ec2
```

### 2. 特定コマンド削除

#### list 系コマンドのキャッシュを削除

```bash
./aws_cache.sh --clear list
```

**マッチするファイル例:**

```
✅ aws s3api list-buckets
✅ aws ec2 describe-instances (list-like)
✅ aws iam list-users
✅ aws codepipeline list-pipelines
❌ aws s3api get-bucket-location
❌ aws codepipeline get-pipeline-state
```

#### describe 系コマンドのキャッシュを削除

```bash
./aws_cache.sh --clear describe
```

### 3. リージョン別削除

#### 特定リージョンのキャッシュを削除

```bash
./aws_cache.sh --clear us-east-1
./aws_cache.sh --clear ap-northeast-1
```

### 4. アカウント/プロファイル別削除

#### 特定プロファイルのキャッシュを削除

```bash
./aws_cache.sh --clear prod-profile
./aws_cache.sh --clear dev-profile
```

## 🔍 実際のキャッシュ分析

### 現在のキャッシュ状況を確認

```bash
# キャッシュ一覧を表示
./aws_cache.sh --list

# 特定パターンのキャッシュ数を確認
./aws_cache.sh --list | grep codepipeline | wc -l
```

### パターンマッチのテスト

```bash
# 削除前にマッチするファイルを確認
ls -la ./aws_cache/*codepipeline*.json

# 実際に削除
./aws_cache.sh --clear codepipeline

# 削除後の確認
ls -la ./aws_cache/*codepipeline*.json
```

## 📊 高度な使用例

### 1. 期限切れキャッシュの一括削除

#### 手動での期限切れキャッシュ特定

```bash
# 期限切れキャッシュを確認
./aws_cache.sh --list | grep "期限切れ"

# 特定の古いキャッシュを削除
./aws_cache.sh --clear "2025/10/05"  # 特定日付のキャッシュ
```

### 2. サイズの大きいキャッシュの削除

#### 大きなファイルを特定

```bash
# キャッシュファイルをサイズ順でソート
ls -lah ./aws_cache/*.json | sort -k5 -hr | head -10

# 大きなファイルの内容を確認
./aws_cache.sh --list | head -5
```

### 3. 開発環境別の管理

#### 開発環境のキャッシュクリア

```bash
./aws_cache.sh --clear dev
./aws_cache.sh --clear staging
./aws_cache.sh --clear prod
```

#### 特定アカウントのキャッシュクリア

```bash
./aws_cache.sh --clear 123456789012  # アカウントID
```

## 🛠️ 運用シナリオ

### 1. 定期メンテナンス

```bash
#!/bin/bash
# daily_cache_cleanup.sh

echo "🧹 日次キャッシュクリーンアップ開始"

# 1週間以上古いキャッシュを削除
find ./aws_cache -name "*.json" -mtime +7 -delete

# 特定サービスの古いキャッシュを削除
./aws_cache.sh --clear codepipeline
./aws_cache.sh --clear ec2

echo "✅ クリーンアップ完了"
```

### 2. 環境切り替え時

```bash
#!/bin/bash
# switch_environment.sh

ENVIRONMENT=$1

echo "🔄 環境切り替え: $ENVIRONMENT"

# 現在の環境のキャッシュをクリア
./aws_cache.sh --clear

# 新しい環境でのキャッシュ作成
export AWS_PROFILE=$ENVIRONMENT
./get_pipelines.sh -q > /dev/null

echo "✅ 環境切り替え完了"
```

### 3. トラブルシューティング

```bash
#!/bin/bash
# troubleshoot_cache.sh

echo "🔍 キャッシュトラブルシューティング"

# 問題のあるサービスのキャッシュをクリア
./aws_cache.sh --clear codepipeline

# 強制的に新しいデータを取得
./get_pipelines.sh -f -q > /dev/null

echo "🔄 キャッシュを再構築しました"
```

## ⚠️ 注意事項

### 1. パフォーマンスへの影響

```bash
# ❌ 避けるべき：頻繁な全削除
./aws_cache.sh --clear  # 全キャッシュ削除

# ✅ 推奨：必要な部分のみ削除
./aws_cache.sh --clear codepipeline
```

### 2. パターンの精度

```bash
# ❌ 曖昧なパターン
./aws_cache.sh --clear a  # 多くのファイルにマッチしてしまう

# ✅ 具体的なパターン
./aws_cache.sh --clear codepipeline
./aws_cache.sh --clear list-buckets
```

### 3. 削除前の確認

```bash
# 削除前に必ず確認
./aws_cache.sh --list | grep "pattern"

# 確認後に削除
./aws_cache.sh --clear pattern
```

## 🚀 自動化スクリプト例

### スマートキャッシュクリーナー

```bash
#!/bin/bash
# smart_cache_cleaner.sh

# 使用方法を表示
show_usage() {
    echo "使用方法: $0 [service|age|size|all]"
    echo "  service: サービス別クリーンアップ"
    echo "  age: 古いキャッシュのクリーンアップ"
    echo "  size: 大きなキャッシュのクリーンアップ"
    echo "  all: 全キャッシュクリーンアップ"
}

case $1 in
    service)
        echo "🧹 サービス別クリーンアップ"
        ./aws_cache.sh --clear codepipeline
        ./aws_cache.sh --clear ec2
        ./aws_cache.sh --clear s3
        ;;
    age)
        echo "🕐 古いキャッシュクリーンアップ"
        find ./aws_cache -name "*.json" -mtime +3 -delete
        ;;
    size)
        echo "📦 大きなキャッシュクリーンアップ"
        find ./aws_cache -name "*.json" -size +1M -delete
        ;;
    all)
        echo "🗑️ 全キャッシュクリーンアップ"
        ./aws_cache.sh --clear
        ;;
    *)
        show_usage
        ;;
esac
```

この詳細ガイドにより、`--clear`オプションを効果的に活用してキャッシュ管理を最適化できます。
