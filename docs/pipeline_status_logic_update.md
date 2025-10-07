# Pipeline Status判定ロジックの改善

## 🔄 変更内容

### 修正前の問題
- 最初のステージ（`stageStates[0]`）のステータスのみを表示
- 他のステージで失敗があっても検出できない
- パイプライン全体の実際の状況を反映していない

### 修正後の改善
- **全ステージの状況を総合判定**
- より正確なパイプライン状態の表示
- 運用監視の精度向上

## 📋 新しい判定ロジック

### 優先順位による判定
```bash
[.state.stageStates[]?.latestExecution?.status] as $statuses |
if ($statuses | map(select(. == "InProgress")) | length) > 0 then "InProgress"
elif ($statuses | map(select(. == "Failed")) | length) > 0 then "Failed"
elif ($statuses | map(select(. == "Stopped")) | length) > 0 then "Stopped"
elif ($statuses | map(select(. == "Succeeded")) | length) == ($statuses | length) and ($statuses | length) > 0 then "Succeeded"
else "Unknown"
end
```

### 判定ルール

| 条件 | 表示ステータス | 説明 |
|------|---------------|------|
| 1つでも`InProgress`がある | **InProgress** | 最優先：実行中のステージがある |
| `InProgress`なし + 1つでも`Failed`がある | **Failed** | どこかで失敗している |
| `InProgress`・`Failed`なし + 1つでも`Stopped`がある | **Stopped** | 停止中のステージがある |
| 全ステージが`Succeeded` | **Succeeded** | 全て成功 |
| その他 | **Unknown** | 不明な状態 |

## 🔍 実例での検証

### Case 1: 部分失敗パイプライン
```json
{
  "name": "031314369150-customizations-pipeline",
  "stageStatuses": [
    {"stage": "Source", "status": "Succeeded"},
    {"stage": "AFT-Global-Customizations", "status": "Succeeded"},
    {"stage": "AFT-Account-Customizations", "status": "Failed"}
  ],
  "overallStatus": "Failed"  // ✅ 正しく失敗と判定
}
```

**修正前**: `Succeeded`（最初のステージのみ参照）
**修正後**: `Failed`（全ステージを総合判定）

### Case 2: 全成功パイプライン
```json
{
  "stageStatuses": [
    {"stage": "Source", "status": "Succeeded"},
    {"stage": "Build", "status": "Succeeded"},
    {"stage": "Deploy", "status": "Succeeded"}
  ],
  "overallStatus": "Succeeded"  // ✅ 全て成功
}
```

### Case 3: 実行中パイプライン（最優先）
```json
{
  "stageStatuses": [
    {"stage": "Source", "status": "Failed"},      // 失敗があっても
    {"stage": "Build", "status": "InProgress"},   // InProgressが優先
    {"stage": "Deploy", "status": null}
  ],
  "overallStatus": "InProgress"  // ✅ 実行中が最優先で判定
}
```

**重要**: InProgressは最優先で判定されるため、他のステージで失敗があっても実行中と表示されます。これにより、現在アクティブなパイプラインを即座に識別できます。

## 📊 表示結果の比較

### 修正前
```
Pipeline Name                  Status          Last Execution       
============================================================================================================
031314369150-customizations-p  ✅ Succeeded   2025/10/06 16:26:30  # ❌ 誤解を招く表示
```

### 修正後
```
Pipeline Name                  Status          Last Execution       
============================================================================================================
031314369150-customizations-p  ❌ Failed      2025/10/06 16:26:30  # ✅ 正確な状態表示
```

## 🛠️ 技術的実装詳細

### jqクエリの解説

#### 1. 全ステージステータス取得
```bash
[.state.stageStates[]?.latestExecution?.status] as $statuses
```
- 全ステージの実行ステータスを配列として取得
- 変数`$statuses`に格納

#### 2. 条件分岐による判定
```bash
if ($statuses | map(select(. == "Failed")) | length) > 0 then "Failed"
```
- `Failed`ステータスをフィルタリング
- 1つでも存在すれば"Failed"と判定

#### 3. 全成功の判定
```bash
elif ($statuses | map(select(. == "Succeeded")) | length) == ($statuses | length) and ($statuses | length) > 0 then "Succeeded"
```
- `Succeeded`の数が全ステージ数と一致
- かつ、ステージが1つ以上存在する場合

### 統計情報の更新
```bash
succeeded_count=$(echo "$pipelines_json" | jq '[.[] | select(
    [.state.stageStates[]?.latestExecution?.status] as $statuses |
    ($statuses | map(select(. == "Succeeded")) | length) == ($statuses | length) and ($statuses | length) > 0
)] | length')
```

## 🎯 運用上のメリット

### 1. 正確な監視
- ✅ パイプライン全体の実際の状態を把握
- ✅ 部分失敗の見落とし防止
- ✅ 運用アラートの精度向上

### 2. 迅速な問題対応
- ✅ 失敗したパイプラインを即座に特定
- ✅ 実行中のパイプラインの進捗確認
- ✅ 停止中パイプラインの検出

### 3. 統計情報の改善
- ✅ より正確な成功/失敗率
- ✅ 実際の運用状況の反映
- ✅ SLA監視の精度向上

## 🔮 今後の拡張可能性

### 1. ステージ別詳細表示
```bash
# 失敗したステージの特定
.state.stageStates[] | select(.latestExecution?.status == "Failed") | .stageName
```

### 2. 実行時間の監視
```bash
# 長時間実行中のパイプライン検出
.state.stageStates[] | select(.latestExecution?.status == "InProgress") | 
{stage: .stageName, duration: (now - (.latestExecution?.startTime | strptime("%Y-%m-%dT%H:%M:%S.%fZ") | mktime))}
```

### 3. 失敗パターンの分析
```bash
# 頻繁に失敗するステージの特定
group_by(.state.stageStates[] | select(.latestExecution?.status == "Failed") | .stageName) | 
map({stage: .[0], count: length})
```

この改善により、CodePipelineの監視と運用管理が大幅に向上し、より信頼性の高いCI/CDパイプラインの運用が可能になりました。