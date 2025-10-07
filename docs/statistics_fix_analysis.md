# パイプライン統計情報の重複カウント修正

## 🔍 問題の特定

### 発見された問題
統計情報で合計数が一致しない問題が発生していました。

**問題の例:**
```
📊 統計: 総数=177, 成功=176, 失敗=1, 実行中=1
合計: 176 + 1 + 1 = 178 ≠ 177 (重複カウント)
```

### 原因分析

#### 1. 独立したステータス判定
**修正前の統計計算:**
```bash
# 各ステータスを独立して判定
succeeded_count = パイプライン中に全ステージがSucceeded
failed_count = パイプライン中に1つでもFailed
inprogress_count = パイプライン中に1つでもInProgress
```

#### 2. 重複カウントの発生
**問題のあるパイプライン例:**
```json
{
  "stages": [
    {"stage": "Source", "status": "Succeeded"},
    {"stage": "Build", "status": "InProgress"},
    {"stage": "Deploy", "status": "Failed"}
  ]
}
```

**カウント結果:**
- 表示ステータス: `InProgress`（優先ルール）
- failed_count: +1（Failedステージがあるため）
- inprogress_count: +1（InProgressステージがあるため）
- **結果**: 1つのパイプラインが2回カウントされる

## ⚡ 実装した修正

### 修正方針
表示ステータスと同じ優先順位ロジックを統計計算にも適用

### 新しい統計計算ロジック

#### 1. 優先順位による排他的判定
```bash
# InProgress（最優先）
inprogress_count = InProgressステージがある

# Failed（InProgressがない場合のみ）
failed_count = InProgressなし AND Failedステージがある

# Stopped（InProgress・Failedがない場合のみ）
stopped_count = InProgress・Failedなし AND Stoppedステージがある

# Succeeded（上記すべてがない場合のみ）
succeeded_count = 上記なし AND 全ステージがSucceeded

# Unknown（その他）
unknown_count = 上記のいずれにも該当しない
```

#### 2. 修正後のjqクエリ
```bash
# InProgress（最優先）
inprogress_count=$(echo "$pipelines_json" | jq '[.[] | select(
    [.state.stageStates[]?.latestExecution?.status] as $statuses |
    ($statuses | map(select(. == "InProgress")) | length) > 0
)] | length')

# Failed（InProgressがない場合のみ）
failed_count=$(echo "$pipelines_json" | jq '[.[] | select(
    [.state.stageStates[]?.latestExecution?.status] as $statuses |
    ($statuses | map(select(. == "InProgress")) | length) == 0 and
    ($statuses | map(select(. == "Failed")) | length) > 0
)] | length')

# 以下同様の排他的ロジック...
```

## 📊 修正結果の検証

### 修正前の問題
```
📊 統計: 総数=177, 成功=176, 失敗=1, 実行中=1
合計: 176 + 1 + 1 = 178 ≠ 177 ❌
```

### 修正後の結果
```
📊 統計: 総数=177, 実行中=1, 失敗=0, 停止=0, 成功=176, 不明=0
合計: 1 + 0 + 0 + 176 + 0 = 177 ✅
```

### 実例での検証
**パイプライン: 031314369150-customizations-pipeline**
```json
{
  "stages": [
    {"stage": "Source", "status": "Succeeded"},
    {"stage": "AFT-Global-Customizations", "status": "InProgress"},
    {"stage": "AFT-Account-Customizations", "status": "Failed"}
  ]
}
```

**判定結果:**
- 表示ステータス: `🔄 InProgress`（InProgressが最優先）
- 統計カウント: `実行中=1`（InProgressカテゴリのみ）
- 重複なし: ✅

## 🛠️ 技術的詳細

### 排他的条件の実装

#### 1. 条件の階層化
```bash
# 各条件で前の条件を除外
if InProgress exists then "InProgress"
elif (NOT InProgress) AND Failed exists then "Failed"
elif (NOT InProgress) AND (NOT Failed) AND Stopped exists then "Stopped"
elif (NOT InProgress) AND (NOT Failed) AND (NOT Stopped) AND AllSucceeded then "Succeeded"
else "Unknown"
```

#### 2. jqでの条件実装
```bash
($statuses | map(select(. == "InProgress")) | length) == 0 and
($statuses | map(select(. == "Failed")) | length) > 0
```

### 統計表示の改善

#### 1. 優先順位順での表示
```bash
# 修正前: 成功, 失敗, 実行中
echo "📊 統計: 総数=$total_count, 成功=$succeeded_count, 失敗=$failed_count, 実行中=$inprogress_count"

# 修正後: 実行中, 失敗, 停止, 成功, 不明（優先順位順）
echo "📊 統計: 総数=$total_count, 実行中=$inprogress_count, 失敗=$failed_count, 停止=$stopped_count, 成功=$succeeded_count, 不明=$unknown_count"
```

#### 2. 全ステータスの表示
- Stopped と Unknown カテゴリを追加
- より詳細な状況把握が可能

## 🎯 改善効果

### 1. データ整合性の確保
- ✅ 統計の合計が総数と一致
- ✅ 重複カウントの完全排除
- ✅ 表示ステータスと統計の一貫性

### 2. 運用監視の向上
- ✅ 正確な状況把握
- ✅ 優先度に基づく情報表示
- ✅ 詳細なステータス分類

### 3. ユーザビリティの向上
- ✅ 直感的な統計表示
- ✅ 信頼性の高い数値
- ✅ 運用判断の精度向上

## 🔮 今後の拡張可能性

### 1. 詳細統計の追加
```bash
# ステージ別統計
echo "📊 ステージ統計: Source成功=$source_success, Build失敗=$build_failed"

# 実行時間統計
echo "📊 実行時間: 平均=${avg_time}分, 最長=${max_time}分"
```

### 2. トレンド分析
```bash
# 時系列での成功率
echo "📊 成功率トレンド: 今日=${today_success_rate}%, 昨日=${yesterday_success_rate}%"
```

### 3. アラート機能
```bash
# 閾値ベースのアラート
if [[ $failed_count -gt 5 ]]; then
    echo "⚠️  アラート: 失敗パイプライン数が閾値を超過 ($failed_count > 5)"
fi
```

この修正により、パイプライン統計情報が正確で信頼性の高いものになり、運用監視の品質が大幅に向上しました。