# AWS CodePipeline クエリフィルター機能

## 🎯 新機能の概要

`get_pipelines.sh`に`--query`オプションを追加し、AWS CLIの強力なクエリフィルター機能を活用してパイプラインを絞り込めるようになりました。

## 🚀 基本的な使用方法

### 構文
```bash
./get_pipelines.sh --query 'JMESPATH_QUERY'
```

### 基本例
```bash
# customizationsパイプラインのみ表示
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]'

# ct-aftで始まるパイプラインのみ表示
./get_pipelines.sh --query 'pipelines[?starts_with(name, `ct-aft`)]'
```

## 📋 実用的なクエリパターン

### 1. 名前パターンによるフィルタリング

#### 特定の接尾辞でフィルタリング
```bash
# customizationsパイプライン
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]'

# deploymentパイプライン
./get_pipelines.sh --query 'pipelines[?ends_with(name, `deployment-pipeline`)]'
```

#### 特定の接頭辞でフィルタリング
```bash
# ct-aftパイプライン
./get_pipelines.sh --query 'pipelines[?starts_with(name, `ct-aft`)]'

# prodで始まるパイプライン
./get_pipelines.sh --query 'pipelines[?starts_with(name, `prod`)]'
```

#### 部分文字列でフィルタリング
```bash
# stagingを含むパイプライン
./get_pipelines.sh --query 'pipelines[?contains(name, `staging`)]'

# testを含むパイプライン
./get_pipelines.sh --query 'pipelines[?contains(name, `test`)]'
```

### 2. アカウントIDベースのフィルタリング

#### 特定アカウントのcustomizationsパイプライン
```bash
# アカウント123456789012のcustomizationsパイプライン
./get_pipelines.sh --query 'pipelines[?starts_with(name, `123456789012-customizations`)]'

# 複数アカウントのパターン
./get_pipelines.sh --query 'pipelines[?starts_with(name, `123456789012`) || starts_with(name, `987654321098`)]'
```

### 3. 複合条件によるフィルタリング

#### AND条件
```bash
# prodを含み、かつpipelineで終わる
./get_pipelines.sh --query 'pipelines[?contains(name, `prod`) && ends_with(name, `pipeline`)]'

# 特定アカウントのcustomizationsパイプライン
./get_pipelines.sh --query 'pipelines[?starts_with(name, `123456789012`) && ends_with(name, `customizations-pipeline`)]'
```

#### OR条件
```bash
# stagingまたはprodを含む
./get_pipelines.sh --query 'pipelines[?contains(name, `staging`) || contains(name, `prod`)]'

# 複数の接尾辞パターン
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`) || ends_with(name, `deployment-pipeline`)]'
```

### 4. 除外フィルタリング

#### NOT条件
```bash
# testを含まないパイプライン
./get_pipelines.sh --query 'pipelines[?!contains(name, `test`)]'

# customizationsパイプライン以外
./get_pipelines.sh --query 'pipelines[?!ends_with(name, `customizations-pipeline`)]'
```

## 🔍 実行結果の例

### customizationsパイプラインのフィルタリング
```bash
$ ./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]' -q
🔍 CodePipeline一覧を取得中（フィルター適用・キャッシュ利用）...
🚀 AWS CodePipeline 一覧
============================================================================================================
Pipeline Name                  Status          Last Execution       Updated                   Version        
============================================================================================================
004078808664-customizations-p  ✅ Succeeded   2025/09/13 00:06:50  2025/09/12 17:36:48       4              
010438466014-customizations-p  ✅ Succeeded   2025/09/24 18:53:43  2025/09/12 17:36:48       5              
031314369150-customizations-p  🔄 InProgress 2025/10/07 00:28:03  2025/10/06 16:22:03       1              
============================================================================================================
📊 統計: 総数=175, 実行中=1, 失敗=0, 停止=0, 成功=174, 不明=0
```

### ct-aftパイプラインのフィルタリング
```bash
$ ./get_pipelines.sh --query 'pipelines[?starts_with(name, `ct-aft`)]' -q
🔍 CodePipeline一覧を取得中（フィルター適用・キャッシュ利用）...
🚀 AWS CodePipeline 一覧
============================================================================================================
Pipeline Name                  Status          Last Execution       Updated                   Version        
============================================================================================================
ct-aft-account-provisioning-c  ✅ Succeeded   2025/01/23 16:29:29  2025/03/31 00:18:34       7              
ct-aft-account-request         ✅ Succeeded   2025/10/06 16:03:19  2025/03/31 00:18:34       9              
============================================================================================================
📊 統計: 総数=2, 実行中=0, 失敗=0, 停止=0, 成功=2, 不明=0
```

## 🛠️ 技術的実装詳細

### AWS CLIクエリの統合
```bash
# 内部実装
local aws_command=("aws" "codepipeline" "list-pipelines")
if [[ -n "$query_filter" ]]; then
    aws_command+=("--query" "$query_filter")
fi
```

### キャッシュとの連携
- クエリフィルターもキャッシュキーに含まれる
- 異なるクエリは別々にキャッシュされる
- 同じクエリの再実行は高速化される

### エラーハンドリング
```bash
# 無効なクエリの場合
$ ./get_pipelines.sh --query 'invalid_query'
❌ エラー: AWS CLIコマンドエラー
```

## 📊 パフォーマンスへの影響

### キャッシュ効率
- **フィルター適用**: AWS側でフィルタリングされるため効率的
- **ネットワーク負荷**: 必要なデータのみ取得
- **処理時間**: フィルター後のデータ処理で高速化

### 比較例
```bash
# 全パイプライン取得（177個）
$ time ./get_pipelines.sh -q >/dev/null
real    0m8.938s

# customizationsパイプラインのみ（175個）
$ time ./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]' -q >/dev/null
real    0m8.245s  # 若干の高速化
```
## 
🎯 運用シナリオ

### 1. 環境別監視
```bash
#!/bin/bash
# environment_monitor.sh

echo "=== Production Pipelines ==="
./get_pipelines.sh --query 'pipelines[?contains(name, `prod`)]' -s Failed

echo "=== Staging Pipelines ==="
./get_pipelines.sh --query 'pipelines[?contains(name, `staging`)]' -s Failed

echo "=== Development Pipelines ==="
./get_pipelines.sh --query 'pipelines[?contains(name, `dev`)]' -s Failed
```

### 2. アカウント別レポート
```bash
#!/bin/bash
# account_report.sh

ACCOUNT_IDS=("123456789012" "987654321098" "555666777888")

for account_id in "${ACCOUNT_IDS[@]}"; do
    echo "=== Account: $account_id ==="
    ./get_pipelines.sh --query "pipelines[?starts_with(name, \`${account_id}\`)]" -f csv > "report_${account_id}.csv"
    echo "Report saved: report_${account_id}.csv"
done
```

### 3. 特定パイプラインタイプの監視
```bash
#!/bin/bash
# pipeline_type_monitor.sh

echo "📊 Customizations Pipelines Status:"
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]' | \
    grep -E "(InProgress|Failed)" || echo "All customizations pipelines are healthy"

echo "📊 AFT Core Pipelines Status:"
./get_pipelines.sh --query 'pipelines[?starts_with(name, `ct-aft`)]'
```

## 🔮 高度な使用例

### 1. 正規表現風のパターンマッチング
```bash
# 数字で始まるパイプライン（アカウントID）
./get_pipelines.sh --query 'pipelines[?starts_with(name, `0`) || starts_with(name, `1`) || starts_with(name, `2`) || starts_with(name, `3`) || starts_with(name, `4`) || starts_with(name, `5`) || starts_with(name, `6`) || starts_with(name, `7`) || starts_with(name, `8`) || starts_with(name, `9`)]'
```

### 2. 長さベースのフィルタリング
```bash
# 短い名前のパイプライン（30文字未満）
./get_pipelines.sh --query 'pipelines[?length(name) < `30`]'
```

### 3. 複雑な条件組み合わせ
```bash
# customizationsパイプラインで、かつ特定アカウント群
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`) && (starts_with(name, `123456`) || starts_with(name, `987654`))]'
```

## ⚠️ 注意事項

### 1. クエリ構文
- JMESPath構文を使用
- バッククォート（`）でリテラル文字列を囲む
- シェルエスケープに注意

### 2. パフォーマンス
- 複雑なクエリは処理時間が増加する可能性
- キャッシュ機能により同じクエリの再実行は高速

### 3. シェルエスケープ
```bash
# 正しい例
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]'

# 間違った例（エスケープ不足）
./get_pipelines.sh --query pipelines[?ends_with(name, customizations-pipeline)]
```

### 4. 大量データの処理
- フィルター適用により処理対象データが削減される
- 統計情報はフィルター後の結果に基づく
- 出力形式（table/json/csv）との組み合わせ可能

## 🔧 トラブルシューティング

### よくあるエラーと解決方法

#### 1. 構文エラー
```bash
# エラー例
$ ./get_pipelines.sh --query 'pipelines[?ends_with(name, customizations-pipeline)]'
❌ エラー: Invalid JMESPath expression

# 解決方法：バッククォートでリテラル文字列を囲む
$ ./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]'
```

#### 2. シェルエスケープエラー
```bash
# エラー例
$ ./get_pipelines.sh --query pipelines[?contains(name, test)]
❌ エラー: コマンドライン解析エラー

# 解決方法：全体をシングルクォートで囲む
$ ./get_pipelines.sh --query 'pipelines[?contains(name, `test`)]'
```

#### 3. 空の結果
```bash
# 結果が空の場合
$ ./get_pipelines.sh --query 'pipelines[?contains(name, `nonexistent`)]'
🔍 CodePipeline一覧を取得中（フィルター適用・キャッシュ利用）...
🚀 AWS CodePipeline 一覧
============================================================================================================
Pipeline Name                  Status          Last Execution       Updated                   Version        
============================================================================================================
============================================================================================================
📊 統計: 総数=0, 実行中=0, 失敗=0, 停止=0, 成功=0, 不明=0

# 確認方法：フィルターなしで全体を確認
$ ./get_pipelines.sh -q | grep nonexistent
```

## 📈 今後の拡張可能性

### 1. 追加予定機能
- 日付範囲によるフィルタリング
- ステータス履歴ベースのクエリ
- カスタムフィールドの追加

### 2. 統合可能性
- 他のAWSサービス（CodeBuild、CodeDeploy）との連携
- CloudWatchメトリクスとの組み合わせ
- 自動アラート機能

### 3. 運用自動化
- 定期実行スクリプトとの組み合わせ
- Slack/Teams通知との連携
- ダッシュボード生成

## 📚 参考資料

### JMESPath公式ドキュメント
- [JMESPath Tutorial](https://jmespath.org/tutorial.html)
- [JMESPath Functions](https://jmespath.org/specification.html#functions)

### AWS CLI Query Examples
- [AWS CLI User Guide - Filtering Output](https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-filter.html)
- [CodePipeline CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/codepipeline/)

---

## 🎉 まとめ

`--query`オプションの追加により、以下が実現されました：

✅ **効率的なフィルタリング**: AWS側でのデータ絞り込み  
✅ **柔軟なクエリ**: JMESPathによる強力な検索機能  
✅ **キャッシュ連携**: フィルター結果もキャッシュ対象  
✅ **運用効率化**: 特定パイプラインタイプの監視が容易  
✅ **スクリプト連携**: 自動化スクリプトでの活用が可能  

この機能により、大量のCodePipelineを効率的に管理・監視できるようになりました。