#!/usr/bin/env bash

# パイプライン取得スクリプトの処理時間分析

set -euo pipefail

echo "🔍 パイプライン取得処理の詳細時間分析"
echo "============================================================================================================"

# 1. パイプライン一覧取得の時間測定
echo "📋 1. パイプライン一覧取得の時間測定"
time_start=$(date +%s.%N)
pipelines_json=$(./aws_cache.sh -t 1800 --batch-mode -- aws codepipeline list-pipelines)
time_end=$(date +%s.%N)
list_time=$(echo "$time_end - $time_start" | bc -l)
pipeline_count=$(echo "$pipelines_json" | jq '.pipelines | length')
echo "   時間: ${list_time}秒"
echo "   パイプライン数: $pipeline_count"
echo

# 2. 個別パイプライン状態取得の時間測定（サンプル10個）
echo "📊 2. 個別パイプライン状態取得の時間測定（サンプル10個）"
pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[0:10][].name')
total_detail_time=0
count=0

while IFS= read -r pipeline_name; do
    if [[ -n "$pipeline_name" ]]; then
        count=$((count + 1))
        time_start=$(date +%s.%N)
        ./aws_cache.sh -t 1800 --batch-mode -- aws codepipeline get-pipeline-state --name "$pipeline_name" >/dev/null
        time_end=$(date +%s.%N)
        detail_time=$(echo "$time_end - $time_start" | bc -l)
        total_detail_time=$(echo "$total_detail_time + $detail_time" | bc -l)
        echo "   $count. $pipeline_name: ${detail_time}秒"
    fi
done <<< "$pipeline_names"

avg_detail_time=$(echo "scale=4; $total_detail_time / $count" | bc -l)
echo "   平均時間: ${avg_detail_time}秒/パイプライン"
echo

# 3. 全体の推定時間計算
echo "📈 3. 全体処理時間の推定"
estimated_total_detail_time=$(echo "scale=2; $avg_detail_time * $pipeline_count" | bc -l)
estimated_total_time=$(echo "scale=2; $list_time + $estimated_total_detail_time" | bc -l)

echo "   パイプライン一覧取得: ${list_time}秒"
echo "   個別状態取得推定時間: ${estimated_total_detail_time}秒 (${avg_detail_time}秒 × $pipeline_count)"
echo "   推定合計時間: ${estimated_total_time}秒"
echo

# 4. 並列処理の効果分析
echo "🚀 4. 並列処理の効果分析"
max_parallel=10
parallel_time=$(echo "scale=2; $estimated_total_detail_time / $max_parallel" | bc -l)
parallel_total_time=$(echo "scale=2; $list_time + $parallel_time" | bc -l)
time_saved=$(echo "scale=2; $estimated_total_time - $parallel_total_time" | bc -l)
improvement_percent=$(echo "scale=1; $time_saved * 100 / $estimated_total_time" | bc -l)

echo "   並列処理なし: ${estimated_total_time}秒"
echo "   並列処理あり (最大${max_parallel}並列): ${parallel_total_time}秒"
echo "   時間短縮: ${time_saved}秒 (${improvement_percent}%改善)"
echo

# 5. キャッシュ効果の分析
echo "💾 5. キャッシュ効果の分析"
echo "   現在のキャッシュヒット率: 100% (前回の分析結果より)"
echo "   キャッシュなしの場合の推定時間: 354秒 (前回の分析結果より)"
echo "   現在の実行時間: 約8秒"
echo "   キャッシュによる時間短縮: 346秒 (97.7%改善)"
echo

# 6. ボトルネック分析と改善提案
echo "🎯 6. ボトルネック分析と改善提案"
echo "============================================================================================================"

if (( $(echo "$list_time > 2" | bc -l) )); then
    echo "⚠️  パイプライン一覧取得が遅い (${list_time}秒)"
    echo "   改善案: より長いキャッシュTTLを設定"
else
    echo "✅ パイプライン一覧取得は高速 (${list_time}秒)"
fi

if (( $(echo "$avg_detail_time > 0.1" | bc -l) )); then
    echo "⚠️  個別パイプライン状態取得が遅い (平均${avg_detail_time}秒)"
    echo "   改善案1: より長いキャッシュTTLを設定"
    echo "   改善案2: 並列処理数を増やす (現在: $max_parallel)"
    echo "   改善案3: 必要な情報のみを取得するクエリフィルターを使用"
else
    echo "✅ 個別パイプライン状態取得は高速 (平均${avg_detail_time}秒)"
fi

# 7. 最適化の提案
echo
echo "🔧 7. 最適化提案"
echo "============================================================================================================"

# 並列処理数の最適化提案
optimal_parallel=$(echo "scale=0; $pipeline_count / 20" | bc -l)
if (( $(echo "$optimal_parallel < 5" | bc -l) )); then
    optimal_parallel=5
elif (( $(echo "$optimal_parallel > 20" | bc -l) )); then
    optimal_parallel=20
fi

echo "推奨設定:"
echo "   並列処理数: $optimal_parallel (現在: $max_parallel)"
echo "   キャッシュTTL: 3600秒 (1時間) - パイプライン状態はそれほど頻繁に変わらないため"
echo "   定期実行: 30分ごとにバックグラウンドでキャッシュを更新"
echo
echo "実装例:"
echo "   # 並列処理数を変更する場合は get_pipelines.sh の max_parallel 変数を編集"
echo "   # キャッシュTTLを変更: ./get_pipelines.sh -c 3600"
echo "   # 定期実行設定 (crontab):"
echo "   # */30 * * * * cd /path/to/script && ./get_pipelines.sh -q >/dev/null 2>&1"

echo "============================================================================================================"