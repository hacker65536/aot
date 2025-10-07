#!/usr/bin/env bash

# より詳細な処理時間分析

set -euo pipefail

echo "🔍 詳細な処理時間分析"
echo "============================================================================================================"

# 実際のget_pipelines.shの各段階の時間を測定
echo "📊 実際のスクリプト実行時間の内訳分析"

# 1. パイプライン一覧取得のみ
echo "1. パイプライン一覧取得のみ:"
time_start=$(date +%s.%N)
pipelines_json=$(./aws_cache.sh -t 1800 --batch-mode -- aws codepipeline list-pipelines)
time_end=$(date +%s.%N)
list_time=$(echo "$time_end - $time_start" | bc -l)
pipeline_count=$(echo "$pipelines_json" | jq '.pipelines | length')
echo "   時間: ${list_time}秒"
echo "   パイプライン数: $pipeline_count"

# 2. JSON処理時間の測定
echo
echo "2. JSON処理時間:"
time_start=$(date +%s.%N)
pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[].name')
time_end=$(date +%s.%N)
json_processing_time=$(echo "$time_end - $time_start" | bc -l)
echo "   パイプライン名抽出: ${json_processing_time}秒"

# 3. 並列処理のオーバーヘッド測定
echo
echo "3. 並列処理のオーバーヘッド測定:"

# 一時ディレクトリ作成時間
time_start=$(date +%s.%N)
temp_dir=$(mktemp -d)
time_end=$(date +%s.%N)
temp_dir_time=$(echo "$time_end - $time_start" | bc -l)
echo "   一時ディレクトリ作成: ${temp_dir_time}秒"

# 10個のパイプラインで並列処理テスト
echo
echo "4. 並列処理テスト (10パイプライン):"
sample_names=$(echo "$pipeline_names" | head -10)

# 逐次処理
time_start=$(date +%s.%N)
count=0
while IFS= read -r pipeline_name; do
    if [[ -n "$pipeline_name" ]]; then
        count=$((count + 1))
        ./aws_cache.sh -t 1800 --batch-mode -- aws codepipeline get-pipeline-state --name "$pipeline_name" >/dev/null
    fi
done <<< "$sample_names"
time_end=$(date +%s.%N)
sequential_time=$(echo "$time_end - $time_start" | bc -l)
echo "   逐次処理 (10個): ${sequential_time}秒"

# 並列処理
time_start=$(date +%s.%N)
count=0
while IFS= read -r pipeline_name; do
    if [[ -n "$pipeline_name" ]]; then
        count=$((count + 1))
        {
            ./aws_cache.sh -t 1800 --batch-mode -- aws codepipeline get-pipeline-state --name "$pipeline_name" >/dev/null
            echo "done" > "$temp_dir/${count}.done"
        } &
    fi
done <<< "$sample_names"
wait
time_end=$(date +%s.%N)
parallel_time=$(echo "$time_end - $time_start" | bc -l)
echo "   並列処理 (10個): ${parallel_time}秒"

# 並列処理の効果
speedup=$(echo "scale=2; $sequential_time / $parallel_time" | bc -l)
echo "   並列処理による高速化: ${speedup}倍"

# 5. ファイルI/O時間の測定
echo
echo "5. ファイルI/O時間の測定:"

# 一時ファイル書き込み
time_start=$(date +%s.%N)
for i in {1..10}; do
    echo '{"test": "data"}' > "$temp_dir/test_${i}.json"
done
time_end=$(date +%s.%N)
write_time=$(echo "$time_end - $time_start" | bc -l)
echo "   10ファイル書き込み: ${write_time}秒"

# 一時ファイル読み込み
time_start=$(date +%s.%N)
for i in {1..10}; do
    cat "$temp_dir/test_${i}.json" >/dev/null
done
time_end=$(date +%s.%N)
read_time=$(echo "$time_end - $time_start" | bc -l)
echo "   10ファイル読み込み: ${read_time}秒"

# 6. jq処理時間の測定
echo
echo "6. jq処理時間の測定:"

# 大きなJSONの処理時間
time_start=$(date +%s.%N)
echo "$pipelines_json" | jq '.pipelines | sort_by(.name)' >/dev/null
time_end=$(date +%s.%N)
jq_sort_time=$(echo "$time_end - $time_start" | bc -l)
echo "   パイプライン一覧ソート: ${jq_sort_time}秒"

# 複雑なjq処理
time_start=$(date +%s.%N)
echo "$pipelines_json" | jq '.pipelines[] | select(.name | contains("customizations"))' >/dev/null
time_end=$(date +%s.%N)
jq_filter_time=$(echo "$time_end - $time_start" | bc -l)
echo "   パイプライン名フィルタリング: ${jq_filter_time}秒"

# クリーンアップ
rm -rf "$temp_dir"

echo
echo "============================================================================================================"
echo "📈 分析結果サマリー:"
echo "============================================================================================================"

# 全体の推定時間計算
total_overhead=$(echo "$json_processing_time + $temp_dir_time + $write_time + $read_time + $jq_sort_time" | bc -l)
actual_api_time=$(echo "$parallel_time - $total_overhead" | bc -l)

echo "処理時間の内訳 (10パイプラインベース):"
echo "   API呼び出し (並列): ${actual_api_time}秒"
echo "   JSON処理: ${json_processing_time}秒"
echo "   ファイルI/O: $(echo "$write_time + $read_time" | bc -l)秒"
echo "   その他オーバーヘッド: $(echo "$temp_dir_time + $jq_sort_time" | bc -l)秒"
echo "   合計オーバーヘッド: ${total_overhead}秒"
echo

# 177パイプラインでの推定
api_time_177=$(echo "scale=2; $actual_api_time * 177 / 10" | bc -l)
overhead_177=$(echo "scale=2; $total_overhead * 177 / 10" | bc -l)
total_estimated=$(echo "scale=2; $list_time + $api_time_177 + $overhead_177" | bc -l)

echo "177パイプライン全体での推定:"
echo "   パイプライン一覧取得: ${list_time}秒"
echo "   API呼び出し (並列): ${api_time_177}秒"
echo "   処理オーバーヘッド: ${overhead_177}秒"
echo "   推定合計時間: ${total_estimated}秒"
echo

# ボトルネック特定
echo "🎯 ボトルネック特定:"
if (( $(echo "$api_time_177 > $overhead_177" | bc -l) )); then
    echo "   主要ボトルネック: API呼び出し (${api_time_177}秒)"
    echo "   改善方法: より長いキャッシュTTL、並列処理数の調整"
else
    echo "   主要ボトルネック: 処理オーバーヘッド (${overhead_177}秒)"
    echo "   改善方法: JSON処理の最適化、ファイルI/O削減"
fi

echo "============================================================================================================"