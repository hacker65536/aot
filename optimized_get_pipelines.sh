#!/usr/bin/env bash

# 最適化されたAWS CodePipeline 一覧取得スクリプト
# 主な改善点: 結果結合処理の最適化

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_CACHE_SCRIPT="$SCRIPT_DIR/aws_cache.sh"

# aws_cache.shの存在確認
if [[ ! -f "$AWS_CACHE_SCRIPT" ]]; then
    echo "❌ エラー: aws_cache.sh が見つかりません: $AWS_CACHE_SCRIPT" >&2
    exit 1
fi

# パイプラインデータを取得
get_pipeline_data() {
    local cache_ttl="$1"
    local debug_flag="$2"
    local region="$3"
    local query_filter="$4"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    local aws_command=("aws" "codepipeline" "list-pipelines")
    if [[ -n "$region" ]]; then
        aws_command+=("--region" "$region")
    fi
    if [[ -n "$query_filter" ]]; then
        aws_command+=("--query" "$query_filter")
    fi
    
    echo "🔍 CodePipeline一覧を取得中（キャッシュ利用）..." >&2
    
    local pipelines_data
    pipelines_data=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" --batch-mode -- "${aws_command[@]}")
    
    echo "$pipelines_data"
}

# 最適化されたパイプラインデータ処理
process_pipeline_data_optimized() {
    local pipelines_json="$1"
    local status_filter="$2"
    local cache_ttl="$3"
    local debug_flag="$4"
    local region="$5"
    local quiet_mode="$6"
    local query_filter="$7"
    
    # パイプライン名のリストを取得
    local pipeline_names
    if [[ -n "$query_filter" ]]; then
        pipeline_names=$(echo "$pipelines_json" | jq -r '.[].name')
    else
        pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[].name')
    fi
    
    local total_pipelines
    total_pipelines=$(echo "$pipeline_names" | wc -l | tr -d ' ')
    
    if [[ $total_pipelines -eq 0 ]]; then
        echo "[]"
        return
    fi
    
    if [[ "$quiet_mode" != "true" ]]; then
        echo "📊 $total_pipelines 個のパイプライン詳細情報を取得中..." >&2
    fi
    
    # 並列処理用の一時ディレクトリ
    local temp_dir=$(mktemp -d)
    local max_parallel=15  # 並列数を増加
    local current_parallel=0
    local current_count=0
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    # 並列でパイプライン詳細を取得
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
                local aws_command=("aws" "codepipeline" "get-pipeline-state" "--name" "$pipeline_name")
                if [[ -n "$region" ]]; then
                    aws_command+=("--region" "$region")
                fi
                
                local pipeline_state
                pipeline_state=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" --batch-mode -- "${aws_command[@]}" 2>/dev/null || echo "{}")
                
                # 基本情報を取得
                local pipeline_info
                if [[ -n "$query_filter" ]]; then
                    pipeline_info=$(echo "$pipelines_json" | jq --arg name "$pipeline_name" '.[] | select(.name == $name)')
                else
                    pipeline_info=$(echo "$pipelines_json" | jq --arg name "$pipeline_name" '.pipelines[] | select(.name == $name)')
                fi
                
                # 結合処理を最適化：jqで直接結合
                echo "$pipeline_info" | jq --argjson state "$pipeline_state" '. + {state: $state}' > "$temp_dir/${current_count}.json"
            } &
            
            current_parallel=$((current_parallel + 1))
            
            # プログレス表示
            if [[ "$quiet_mode" != "true" ]] && [[ $((current_count % 25)) -eq 0 ]]; then
                echo "   進捗: $current_count/$total_pipelines 処理済み" >&2
            fi
        fi
    done <<< "$pipeline_names"
    
    # 残りの並列処理完了を待機
    wait
    
    if [[ "$quiet_mode" != "true" ]]; then
        echo "🔄 結果を結合中..." >&2
    fi
    
    # 最適化された結果結合：jq slurpを使用
    local enhanced_data
    enhanced_data=$(find "$temp_dir" -name "*.json" -exec cat {} \; | jq -s '.')
    
    # 一時ディレクトリを削除
    rm -rf "$temp_dir"
    
    if [[ "$quiet_mode" != "true" ]]; then
        echo "✅ パイプライン詳細情報の取得が完了しました" >&2
    fi
    
    # ステータスフィルター適用とソート
    local jq_filter='.'
    if [[ "$status_filter" != "ALL" ]]; then
        jq_filter="map(select(.state.stageStates[]?.latestExecution?.status == \"$status_filter\"))"
    fi
    
    jq_filter="$jq_filter | sort_by(.name)"
    
    echo "$enhanced_data" | jq "$jq_filter"
}

# テーブル形式で出力（最適化版）
format_table_optimized() {
    local pipelines_json="$1"
    
    echo "🚀 AWS CodePipeline 一覧"
    echo "============================================================================================================"
    printf "%-30s %-15s %-20s %-25s %-15s\n" "Pipeline Name" "Status" "Last Execution" "Updated" "Version"
    echo "============================================================================================================"
    
    # jqクエリを最適化：一度の処理で全ての変換を実行
    echo "$pipelines_json" | jq -r '.[] | 
        [
            .name,
            (
                [.state.stageStates[]?.latestExecution?.status] as $statuses |
                if ($statuses | map(select(. == "InProgress")) | length) > 0 then "🔄 InProgress"
                elif ($statuses | map(select(. == "Failed")) | length) > 0 then "❌ Failed"
                elif ($statuses | map(select(. == "Stopped")) | length) > 0 then "⏹️  Stopped"
                elif ($statuses | map(select(. == "Succeeded")) | length) == ($statuses | length) and ($statuses | length) > 0 then "✅ Succeeded"
                else "❓ Unknown"
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
        ] | @tsv' | \
    while IFS=$'\t' read -r name status last_exec updated version; do
        printf "%-30s %-15s %-20s %-25s %-15s\n" \
            "${name:0:29}" \
            "${status:0:14}" \
            "${last_exec:0:19}" \
            "${updated:0:24}" \
            "${version:0:14}"
    done
    
    echo "============================================================================================================"
    
    # 統計情報（簡略版）
    local total_count succeeded_count failed_count inprogress_count
    total_count=$(echo "$pipelines_json" | jq 'length')
    inprogress_count=$(echo "$pipelines_json" | jq '[.[] | select(
        [.state.stageStates[]?.latestExecution?.status] as $statuses |
        ($statuses | map(select(. == "InProgress")) | length) > 0
    )] | length')
    failed_count=$(echo "$pipelines_json" | jq '[.[] | select(
        [.state.stageStates[]?.latestExecution?.status] as $statuses |
        ($statuses | map(select(. == "InProgress")) | length) == 0 and
        ($statuses | map(select(. == "Failed")) | length) > 0
    )] | length')
    succeeded_count=$(echo "$pipelines_json" | jq '[.[] | select(
        [.state.stageStates[]?.latestExecution?.status] as $statuses |
        ($statuses | map(select(. == "InProgress")) | length) == 0 and
        ($statuses | map(select(. == "Failed")) | length) == 0 and
        ($statuses | map(select(. == "Succeeded")) | length) == ($statuses | length) and ($statuses | length) > 0
    )] | length')
    local stats="総数=$total_count, 実行中=$inprogress_count, 失敗=$failed_count, 成功=$succeeded_count"
    
    echo "📊 統計: $stats"
}

# メイン処理
main() {
    local format="table"
    local status_filter="ALL"
    local cache_ttl="1800"
    local debug_flag="false"
    local region=""
    local quiet_mode="false"
    local query_filter=""
    
    # 引数解析（簡略版）
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--format) format="$2"; shift 2 ;;
            -s|--status) status_filter="$2"; shift 2 ;;
            -c|--cache-ttl) cache_ttl="$2"; shift 2 ;;
            -r|--region) region="$2"; shift 2 ;;
            --query) query_filter="$2"; shift 2 ;;
            -q|--quiet) quiet_mode="true"; shift ;;
            -d|--debug) debug_flag="true"; shift ;;
            -h|--help) 
                echo "最適化版 get_pipelines.sh - 結果結合処理を大幅に高速化"
                echo "使用方法: $0 [オプション]"
                echo "オプション: -f format, -s status, -c cache-ttl, -r region, --query filter, -q, -d"
                exit 0 ;;
            *) echo "不明なオプション: $1"; exit 1 ;;
        esac
    done
    
    # パイプラインデータを取得
    local pipelines_json
    pipelines_json=$(get_pipeline_data "$cache_ttl" "$debug_flag" "$region" "$query_filter")
    
    # 結果が空の場合
    local pipeline_count
    if [[ -n "$query_filter" ]]; then
        pipeline_count=$(echo "$pipelines_json" | jq 'length')
    else
        pipeline_count=$(echo "$pipelines_json" | jq '.pipelines | length')
    fi
    
    if [[ "$pipeline_count" == "0" ]]; then
        echo "⚠️  CodePipelineが見つかりませんでした" >&2
        exit 0
    fi
    
    # パイプラインデータを処理（最適化版）
    local processed_data
    processed_data=$(process_pipeline_data_optimized "$pipelines_json" "$status_filter" "$cache_ttl" "$debug_flag" "$region" "$quiet_mode" "$query_filter")
    
    # フィルター後の結果が空の場合
    if [[ "$(echo "$processed_data" | jq 'length')" == "0" ]]; then
        echo "⚠️  条件に一致するパイプラインが見つかりませんでした" >&2
        exit 0
    fi
    
    # 指定された形式で出力
    case $format in
        table)
            format_table_optimized "$processed_data"
            ;;
        json)
            echo "$processed_data" | jq '.'
            ;;
        csv)
            echo "PipelineName,Status,LastExecution,Updated,Version"
            echo "$processed_data" | jq -r '.[] | [.name, "status", "last_exec", "updated", "version"] | @csv'
            ;;
    esac
}

# スクリプトが直接実行された場合のみmainを呼び出し
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi