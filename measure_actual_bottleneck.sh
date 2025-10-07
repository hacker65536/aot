#!/usr/bin/env bash

# 実際のボトルネックを特定するための測定

set -euo pipefail

echo "🔍 実際のボトルネック特定"
echo "============================================================================================================"

# 1. パイプライン一覧取得
echo "1. パイプライン一覧取得:"
time_start=$(date +%s.%N)
pipelines_json=$(./aws_cache.sh -t 1800 --batch-mode -- aws codepipeline list-pipelines)
time_end=$(date +%s.%N)
list_time=$(echo "$time_end - $time_start" | bc -l)
echo "   時間: ${list_time}秒"

# 2. パイプライン名抽出
echo "2. パイプライン名抽出:"
time_start=$(date +%s.%N)
pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[].name')
pipeline_count=$(echo "$pipeline_names" | wc -l | tr -d ' ')
time_end=$(date +%s.%N)
extract_time=$(echo "$time_end - $time_start" | bc -l)
echo "   時間: ${extract_time}秒"
echo "   パイプライン数: $pipeline_count"

# 3. 一時ディレクトリ作成
echo "3. 一時ディレクトリ作成:"
time_start=$(date +%s.%N)
temp_dir=$(mktemp -d)
time_end=$(date +%s.%N)
temp_time=$(echo "$time_end - $time_start" | bc -l)
echo "   時間: ${temp_time}秒"

# 4. 全パイプラインの詳細取得（実際の並列処理）
echo "4. 全パイプラインの詳細取得（並列処理）:"
time_start=$(date +%s.%N)

max_parallel=10
current_parallel=0
current_count=0

while IFS= read -r pipeline_name; do
    if [[ -n "$pipeline_name" ]]; then
        current_count=$((current_count + 1))
        
        # 並列処理制限
        if [[ $current_parallel -ge $max_parallel ]]; then
            wait
            current_parallel=0
        fi
        
        # バックグラウンドで詳細情報を取得
        {
            pipeline_state=$(./aws_cache.sh -t 1800 --batch-mode -- aws codepipeline get-pipeline-state --name "$pipeline_name" 2>/dev/null || echo "{}")
            
            # 基本情報と状態情報を結合
            pipeline_info=$(echo "$pipelines_json" | jq --arg name "$pipeline_name" '.pipelines[] | select(.name == $name)')
            combined_info=$(echo "$pipeline_info" | jq --argjson state "$pipeline_state" '. + {state: $state}')
            
            # 一時ファイルに保存
            echo "$combined_info" > "$temp_dir/${current_count}.json"
        } &
        
        current_parallel=$((current_parallel + 1))
        
        # 進捗表示（50個ごと）
        if [[ $((current_count % 50)) -eq 0 ]]; then
            echo "   進捗: $current_count/$pipeline_count 処理済み"
        fi
    fi
done <<< "$pipeline_names"

# 残りの並列処理完了を待機
wait

time_end=$(date +%s.%N)
parallel_processing_time=$(echo "$time_end - $time_start" | bc -l)
echo "   時間: ${parallel_processing_time}秒"

# 5. 結果の結合
echo "5. 結果の結合:"
time_start=$(date +%s.%N)

enhanced_data="[]"
for ((i=1; i<=pipeline_count; i++)); do
    if [[ -f "$temp_dir/${i}.json" ]]; then
        item_data=$(cat "$temp_dir/${i}.json")
        enhanced_data=$(echo "$enhanced_data" | jq --argjson item "$item_data" '. + [$item]')
    fi
done

time_end=$(date +%s.%N)
combine_time=$(echo "$time_end - $time_start" | bc -l)
echo "   時間: ${combine_time}秒"

# 6. ソート処理
echo "6. ソート処理:"
time_start=$(date +%s.%N)
sorted_data=$(echo "$enhanced_data" | jq 'sort_by(.name)')
time_end=$(date +%s.%N)
sort_time=$(echo "$time_end - $time_start" | bc -l)
echo "   時間: ${sort_time}秒"

# 7. テーブル形式変換
echo "7. テーブル形式変換:"
time_start=$(date +%s.%N)
echo "$sorted_data" | jq -r '.[] | 
    [
        .name,
        (
            [.state.stageStates[]?.latestExecution?.status] as $statuses |
            if ($statuses | map(select(. == "InProgress")) | length) > 0 then "InProgress"
            elif ($statuses | map(select(. == "Failed")) | length) > 0 then "Failed"
            elif ($statuses | map(select(. == "Stopped")) | length) > 0 then "Stopped"
            elif ($statuses | map(select(. == "Succeeded")) | length) == ($statuses | length) and ($statuses | length) > 0 then "Succeeded"
            else "Unknown"
            end
        ),
        ([.state.stageStates[]?.actionStates[]?.latestExecution?.lastStatusChange] | map(select(. != null)) | max // "N/A" | 
            if . == "N/A" then . 
            else (. | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S"))
            end),
        (.updated // "N/A" | 
            if . == "N/A" then . 
            else (. | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S"))
            end),
        (.version // "N/A" | tostring)
    ] | @tsv' >/dev/null
time_end=$(date +%s.%N)
format_time=$(echo "$time_end - $time_start" | bc -l)
echo "   時間: ${format_time}秒"

# クリーンアップ
rm -rf "$temp_dir"

# 合計時間計算
total_time=$(echo "$list_time + $extract_time + $temp_time + $parallel_processing_time + $combine_time + $sort_time + $format_time" | bc -l)

echo
echo "============================================================================================================"
echo "📊 処理時間の詳細内訳:"
echo "============================================================================================================"
printf "%-30s %10s %8s\n" "処理段階" "時間(秒)" "割合(%)"
echo "------------------------------------------------------------"
printf "%-30s %10.3f %8.1f\n" "1. パイプライン一覧取得" "$list_time" "$(echo "scale=1; $list_time * 100 / $total_time" | bc -l)"
printf "%-30s %10.3f %8.1f\n" "2. パイプライン名抽出" "$extract_time" "$(echo "scale=1; $extract_time * 100 / $total_time" | bc -l)"
printf "%-30s %10.3f %8.1f\n" "3. 一時ディレクトリ作成" "$temp_time" "$(echo "scale=1; $temp_time * 100 / $total_time" | bc -l)"
printf "%-30s %10.3f %8.1f\n" "4. 並列詳細取得" "$parallel_processing_time" "$(echo "scale=1; $parallel_processing_time * 100 / $total_time" | bc -l)"
printf "%-30s %10.3f %8.1f\n" "5. 結果結合" "$combine_time" "$(echo "scale=1; $combine_time * 100 / $total_time" | bc -l)"
printf "%-30s %10.3f %8.1f\n" "6. ソート処理" "$sort_time" "$(echo "scale=1; $sort_time * 100 / $total_time" | bc -l)"
printf "%-30s %10.3f %8.1f\n" "7. テーブル形式変換" "$format_time" "$(echo "scale=1; $format_time * 100 / $total_time" | bc -l)"
echo "------------------------------------------------------------"
printf "%-30s %10.3f %8s\n" "合計" "$total_time" "100.0"

echo
echo "🎯 ボトルネック分析:"
# 最も時間のかかる処理を特定
max_time=0
max_process=""

if (( $(echo "$list_time > $max_time" | bc -l) )); then
    max_time=$list_time
    max_process="パイプライン一覧取得"
fi
if (( $(echo "$extract_time > $max_time" | bc -l) )); then
    max_time=$extract_time
    max_process="パイプライン名抽出"
fi
if (( $(echo "$parallel_processing_time > $max_time" | bc -l) )); then
    max_time=$parallel_processing_time
    max_process="並列詳細取得"
fi
if (( $(echo "$combine_time > $max_time" | bc -l) )); then
    max_time=$combine_time
    max_process="結果結合"
fi
if (( $(echo "$sort_time > $max_time" | bc -l) )); then
    max_time=$sort_time
    max_process="ソート処理"
fi
if (( $(echo "$format_time > $max_time" | bc -l) )); then
    max_time=$format_time
    max_process="テーブル形式変換"
fi

echo "   最大ボトルネック: $max_process (${max_time}秒)"

# 改善提案
echo
echo "💡 改善提案:"
if [[ "$max_process" == "並列詳細取得" ]]; then
    echo "   - 並列処理数を増やす (現在: $max_parallel → 推奨: 15-20)"
    echo "   - キャッシュTTLを長くする (現在: 30分 → 推奨: 1-2時間)"
elif [[ "$max_process" == "結果結合" ]]; then
    echo "   - jqの処理を最適化する"
    echo "   - 一時ファイルの代わりにメモリ内処理を検討"
elif [[ "$max_process" == "テーブル形式変換" ]]; then
    echo "   - jqクエリを最適化する"
    echo "   - 複雑な日時変換処理を簡略化"
fi

echo "============================================================================================================"