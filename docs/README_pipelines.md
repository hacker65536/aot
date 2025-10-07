# AWS CodePipeline 一覧取得ツール

`aws_cache.sh` を活用してAWS CodePipelineの情報を効率的に取得・表示するスクリプトです。

## 特徴

🚀 **高速化**
- `aws_cache.sh` によるAPIレスポンスキャッシュ
- 初回実行後は高速にデータ取得

📊 **詳細情報**
- パイプライン一覧と実行状況
- 最終実行結果とタイムスタンプ
- ステータス別フィルタリング

⚙️ **柔軟な設定**
- 複数の出力形式をサポート
- リージョン指定可能
- キャッシュ有効期限の調整

## 前提条件

```bash
# 必要なファイル
./aws_cache.sh      # キャッシュ機能
./get_pipelines.sh  # パイプライン一覧取得

# 必要なツール
aws                 # AWS CLI
jq                  # JSON処理

# 必要な権限
codepipeline:ListPipelines
codepipeline:GetPipelineState
```

## 使用方法

### 基本的な使用

```bash
# 全パイプラインをテーブル形式で表示（5分キャッシュ）
./get_pipelines.sh

# 初回実行時の動作
# 🔍 CodePipeline一覧を取得中（キャッシュ利用）...
# 🔄 AWS APIを実行: aws codepipeline list-pipelines --output json
# 💾 レスポンスをキャッシュに保存

# 2回目実行時の動作（キャッシュから高速取得）
# 🔍 CodePipeline一覧を取得中（キャッシュ利用）...
# 📦 キャッシュから取得: aws codepipeline list-pipelines --output json
```

### 出力形式の選択

```bash
# テーブル形式（デフォルト）
./get_pipelines.sh -f table

# JSON形式
./get_pipelines.sh -f json

# CSV形式
./get_pipelines.sh -f csv
```

### ステータスフィルター

```bash
# 全パイプライン（デフォルト）
./get_pipelines.sh -s ALL

# 成功したパイプラインのみ
./get_pipelines.sh -s Succeeded

# 失敗したパイプラインのみ
./get_pipelines.sh -s Failed

# 実行中のパイプラインのみ
./get_pipelines.sh -s InProgress

# 停止中のパイプラインのみ
./get_pipelines.sh -s Stopped
```

### リージョン指定

```bash
# 特定リージョンのパイプライン
./get_pipelines.sh -r us-east-1
./get_pipelines.sh -r ap-northeast-1

# 複数リージョンの情報を取得
for region in us-east-1 us-west-2 ap-northeast-1; do
    echo "=== $region ==="
    ./get_pipelines.sh -r $region
done
```

### キャッシュ制御

```bash
# キャッシュ有効期限を10分に設定
./get_pipelines.sh -c 600

# デバッグモード（キャッシュの動作を確認）
./get_pipelines.sh -d

# プログレスバー非表示で実行
./get_pipelines.sh -q

# 強制的にキャッシュを更新
./aws_cache.sh -f -- aws codepipeline list-pipelines
```

## 出力例

### テーブル形式

```
🚀 AWS CodePipeline 一覧
============================================================================================================
Pipeline Name                  Status          Last Execution       Updated                   Version        
============================================================================================================
my-web-app-pipeline           ✅ Succeeded     2024/01/15 14:30:25   2024/01/15 14:25:10      3              
api-deployment-pipeline       ❌ Failed        2024/01/15 13:45:12   2024/01/15 13:40:05      7              
infrastructure-pipeline       🔄 InProgress    2024/01/15 15:10:30   2024/01/15 15:05:20      2              
data-processing-pipeline      ⏹️  Stopped      2024/01/14 16:20:45   2024/01/14 16:15:30      5              
============================================================================================================
📊 統計: 総数=4, 成功=1, 失敗=1, 実行中=1
```

### JSON形式

```json
[
  {
    "name": "my-web-app-pipeline",
    "version": 3,
    "created": "2024-01-10T10:00:00.000Z",
    "updated": "2024-01-15T14:25:10.000Z",
    "state": {
      "pipelineName": "my-web-app-pipeline",
      "pipelineVersion": 3,
      "stageStates": [
        {
          "stageName": "Source",
          "latestExecution": {
            "pipelineExecutionId": "12345678-1234-1234-1234-123456789012",
            "status": "Succeeded",
            "lastStatusChange": "2024-01-15T14:30:25.000Z"
          }
        }
      ]
    }
  }
]
```

### CSV形式

```csv
PipelineName,Status,LastExecution,Updated,Version
my-web-app-pipeline,Succeeded,2024/01/15 14:30:25,2024/01/15 14:25:10,3
api-deployment-pipeline,Failed,2024/01/15 13:45:12,2024/01/15 13:40:05,7
infrastructure-pipeline,InProgress,2024/01/15 15:10:30,2024/01/15 15:05:20,2
```

## 実用的な使用例

### 1. 失敗したパイプラインの調査

```bash
# 失敗したパイプラインを特定
./get_pipelines.sh -s Failed

# 失敗の詳細情報を取得
./get_pipelines.sh -s Failed -f json | jq '.[] | {
    name: .name,
    failedStage: .state.stageStates[] | select(.latestExecution.status == "Failed") | .stageName,
    errorDetails: .state.stageStates[].actionStates[]?.latestExecution?.errorDetails
}'
```

### 2. パイプライン監視ダッシュボード

```bash
#!/bin/bash
# pipeline_monitor.sh

echo "=== CodePipeline 監視ダッシュボード ==="
echo "更新時刻: $(date)"
echo

echo "🔄 実行中のパイプライン:"
./get_pipelines.sh -s InProgress -f table

echo
echo "❌ 失敗したパイプライン:"
./get_pipelines.sh -s Failed -f table

echo
echo "📊 全体統計:"
./get_pipelines.sh -f json | jq -r '
    "総パイプライン数: " + (length | tostring),
    "成功: " + ([.[] | select(.state.stageStates[0]?.latestExecution?.status == "Succeeded")] | length | tostring),
    "失敗: " + ([.[] | select(.state.stageStates[0]?.latestExecution?.status == "Failed")] | length | tostring),
    "実行中: " + ([.[] | select(.state.stageStates[0]?.latestExecution?.status == "InProgress")] | length | tostring)
'
```

### 3. パイプライン実行履歴の分析

```bash
# 特定パイプラインの実行履歴
PIPELINE_NAME="my-web-app-pipeline"
aws codepipeline list-pipeline-executions --pipeline-name "$PIPELINE_NAME" | \
jq '.pipelineExecutionSummaries[] | {
    executionId: .pipelineExecutionId,
    status: .status,
    startTime: .startTime,
    lastUpdateTime: .lastUpdateTime
}'

# 最近の実行結果サマリー
./get_pipelines.sh -f json | jq '.[] | {
    name: .name,
    lastExecution: .state.stageStates[0]?.latestExecution?.lastStatusChange,
    status: .state.stageStates[0]?.latestExecution?.status
} | select(.lastExecution != null)' | \
jq -s 'sort_by(.lastExecution) | reverse | .[0:10]'
```

### 4. レポート生成

```bash
# 日次レポート生成
DATE=$(date +%Y%m%d)
REPORT_FILE="pipeline_report_${DATE}.csv"

./get_pipelines.sh -f csv > "$REPORT_FILE"
echo "📄 レポートを生成しました: $REPORT_FILE"

# 週次サマリー
./get_pipelines.sh -f json | jq -r '
    group_by(.state.stageStates[0]?.latestExecution?.status) | 
    map({
        status: .[0].state.stageStates[0]?.latestExecution?.status,
        count: length,
        pipelines: [.[].name]
    })
' > "pipeline_summary_${DATE}.json"
```

### 5. アラート機能

```bash
# 失敗したパイプラインがある場合にSlack通知
FAILED_COUNT=$(./get_pipelines.sh -s Failed -f json | jq 'length')

if [[ "$FAILED_COUNT" -gt 0 ]]; then
    FAILED_PIPELINES=$(./get_pipelines.sh -s Failed -f json | jq -r '.[].name' | tr '\n' ', ')
    
    # Slack Webhook URL (環境変数で設定)
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"⚠️ CodePipeline Alert: $FAILED_COUNT pipeline(s) failed: $FAILED_PIPELINES\"}" \
            "$SLACK_WEBHOOK_URL"
    fi
fi
```

## キャッシュの管理

```bash
# キャッシュ一覧を確認
./aws_cache.sh --list

# CodePipeline関連のキャッシュをクリア
./aws_cache.sh --clear codepipeline

# 全キャッシュをクリア
./aws_cache.sh --clear
```

## トラブルシューティング

### よくある問題

1. **CodePipeline APIへのアクセス権限がない**
   ```
   ❌ エラー: AWS CLIコマンドエラー
   ```
   → 必要な権限: `codepipeline:ListPipelines`, `codepipeline:GetPipelineState`

2. **リージョンにパイプラインが存在しない**
   ```
   ⚠️  CodePipelineが見つかりませんでした
   ```
   → 正しいリージョンを指定してください

3. **パイプライン詳細の取得に時間がかかる**
   → パイプライン数が多い場合、初回実行時は時間がかかります。キャッシュ利用で高速化されます

### デバッグ方法

```bash
# デバッグモードで実行
./get_pipelines.sh -d

# AWS CLIを直接実行して確認
aws codepipeline list-pipelines
aws codepipeline get-pipeline-state --name "pipeline-name"

# キャッシュの状態を確認
./aws_cache.sh --list
```

## パフォーマンス

- **初回実行**: パイプライン数 × 2-3秒（API呼び出し）
- **キャッシュ利用時**: ~0.5-1秒（ローカルファイル読み込み）
- **推奨キャッシュ期間**: 5-10分（パイプライン状況は頻繁に変更されるため）

## 応用例

### CI/CDパイプラインでの利用

```yaml
# .github/workflows/pipeline-check.yml
name: Pipeline Status Check
on:
  schedule:
    - cron: '*/15 * * * *'  # 15分毎

jobs:
  check-pipelines:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Check Failed Pipelines
        run: |
          ./get_pipelines.sh -s Failed -f json > failed_pipelines.json
          if [[ $(jq 'length' failed_pipelines.json) -gt 0 ]]; then
            echo "::error::Failed pipelines detected"
            jq -r '.[].name' failed_pipelines.json
            exit 1
          fi
```