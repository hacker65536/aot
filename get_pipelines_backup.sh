#!/usr/bin/env bash

# AWS CodePipeline 一覧取得スクリプト
# パイプラインの状態、最終実行状況などを表示
# aws_cache.sh を利用してAPIレスポンスをキャッシュし、高速化を実現

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_CACHE_SCRIPT="$SCRIPT_DIR/aws_cache.sh"

# aws_cache.shの存在確認
if [[ ! -f "$AWS_CACHE_SCRIPT" ]]; then
    echo "❌ エラー: aws_cache.sh が見つかりません: $AWS_CACHE_SCRIPT" >&2
    echo "💡 ヒント: aws_cache.sh をダウンロードして同じディレクトリに配置してください" >&2
    exit 1
fi

# aws_cache.shが実行可能かチェック
if [[ ! -x "$AWS_CACHE_SCRIPT" ]]; then
    echo "❌ エラー: aws_cache.sh に実行権限がありません" >&2
    echo "💡 解決方法: chmod +x $AWS_CACHE_SCRIPT" >&2
    exit 1
fi

# キャッシュ利用状況を分析
analyze_cache_usage() {
    local pipelines_json="$1"
    local cache_ttl="$2"
    local region="$3"
    
    local pipeline_names
    pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[].name')
    
    local total_pipelines
    total_pipelines=$(echo "$pipeline_names" | wc -l | tr -d ' ')
    
    local cache_hits=0
    local cache_misses=0
    
    echo "🔍 キャッシュ利用状況を分析中..." >&2
    
    while IFS= read -r pipeline_name; do
        if [[ -n "$pipeline_name" ]]; then
            local aws_command=("aws" "codepipeline" "get-pipeline-state" "--name" "$pipeline_name")
            if [[ -n "$region" ]]; then
                aws_command+=("--region" "$region")
            fi
            
            local command_str="${aws_command[*]}"
            if "$AWS_CACHE_SCRIPT" --test "$command_str" -t "$cache_ttl" >/dev/null 2>&1; then
                cache_hits=$((cache_hits + 1))
            else
                cache_misses=$((cache_misses + 1))
            fi
        fi
    done <<< "$pipeline_names"
    
    local hit_rate=$((cache_hits * 100 / total_pipelines))
    local estimated_time=$((cache_hits / 10 + cache_misses * 2))
    
    echo "📊 キャッシュ分析結果:" >&2
    echo "   総パイプライン数: $total_pipelines" >&2
    echo "   キャッシュヒット: $cache_hits ($hit_rate%)" >&2
    echo "   キャッシュミス: $cache_misses ($((cache_misses * 100 / total_pipelines))%)" >&2
    echo "   予想実行時間: ${estimated_time}秒" >&2
    
    # パフォーマンス評価と推奨事項
    if [[ $hit_rate -ge 80 ]]; then
        echo "   ✅ キャッシュ効率: 優秀 (${hit_rate}%)" >&2
    elif [[ $hit_rate -ge 50 ]]; then
        echo "   ⚠️  キャッシュ効率: 普通 (${hit_rate}%)" >&2
        echo "   💡 推奨: TTLを長くするか、事前にキャッシュを作成してください" >&2
    else
        echo "   ❌ キャッシュ効率: 低い (${hit_rate}%)" >&2
        echo "   💡 推奨事項:" >&2
        echo "      - TTLを長くする: -c 3600 (1時間)" >&2
        echo "      - 事前キャッシュ作成: ./get_pipelines.sh -q >/dev/null" >&2
        echo "      - 古いキャッシュクリア: ./aws_cache.sh --clear codepipeline" >&2
    fi
    echo >&2
}

# プログレスバー表示関数
show_progress() {
    local current="$1"
    local total="$2"
    local pipeline_name="$3"
    local quiet_mode="$4"
    local cache_status="$5"  # "HIT" or "MISS"
    local width=50
    
    # quietモードの場合は表示しない
    if [[ "$quiet_mode" == "true" ]]; then
        return
    fi
    
    # プログレスバーを標準エラー出力に表示（標準出力を汚さないため）
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    # プログレスバーの構築
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    # キャッシュ状況のアイコン
    local cache_icon=""
    case "$cache_status" in
        "HIT") cache_icon="🟢" ;;
        "MISS") cache_icon="🔴" ;;
        "PROCESSING") cache_icon="🔄" ;;
        *) cache_icon="⚪" ;;
    esac
    
    # 進捗表示（カーソルを行の先頭に戻して上書き）
    printf "\r%s パイプライン詳細取得中 [%s] %d/%d (%d%%) - %s" "$cache_icon" "$bar" "$current" "$total" "$percentage" "${pipeline_name:0:25}" >&2
    
    # 完了時は改行
    if [[ $current -eq $total ]]; then
        echo >&2
    fi
}

# ヘルプ表示
show_help() {
    cat << EOF
AWS CodePipeline 一覧取得

使用方法:
  $0 [オプション]

このスクリプトは aws_cache.sh を利用してAPIレスポンスをキャッシュします。
同じ条件での再実行時は高速にデータを取得できます。

オプション:
  -f, --format FORMAT   出力形式 (table|json|csv) [デフォルト: table]
  -s, --status STATUS   ステータスフィルター (ALL|Succeeded|Failed|InProgress|Stopped) [デフォルト: ALL]
  -c, --cache-ttl TTL   キャッシュ有効期限（秒） [デフォルト: 1800]
  -r, --region REGION   AWSリージョン [デフォルト: 現在の設定]
  -q, --quiet          プログレスバーを非表示
  --analyze-cache      キャッシュ利用状況を分析（デバッグ用）
  -d, --debug          デバッグモード（aws_cache.shのデバッグログも表示）
  -h, --help           このヘルプを表示

例:
  $0                           # 全パイプラインをテーブル形式で表示（30分キャッシュ）
  $0 -f json                   # JSON形式で出力
  $0 -f csv                    # CSV形式で出力
  $0 -s Failed                 # 失敗したパイプラインのみ表示
  $0 -r us-east-1             # 特定リージョンのパイプライン
  $0 -c 600 -d                # 10分キャッシュ、デバッグモード
  $0 -q                        # プログレスバー非表示で実行
  $0 --analyze-cache           # キャッシュ利用状況を分析
  
キャッシュ関連:
  初回実行時: AWS APIを呼び出してキャッシュに保存
  2回目以降: キャッシュから高速取得（TTL期間内）
  強制更新: ./aws_cache.sh -f -- aws codepipeline list-pipelines

EOF
}

# パイプラインデータを取得
get_pipeline_data() {
    local cache_ttl="$1"
    local debug_flag="$2"
    local region="$3"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    local aws_command=("aws" "codepipeline" "list-pipelines")
    if [[ -n "$region" ]]; then
        aws_command+=("--region" "$region")
    fi
    
    # aws_cache.sh を使用してCodePipeline一覧を取得
    echo "🔍 CodePipeline一覧を取得中（キャッシュ利用）..." >&2
    
    local pipelines_data
    pipelines_data=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" --batch-mode -- "${aws_command[@]}")
    
    echo "$pipelines_data"
}

# パイプラインの詳細情報を取得（実行状況含む）
get_pipeline_details() {
    local pipeline_name="$1"
    local cache_ttl="$2"
    local debug_flag="$3"
    local region="$4"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    local aws_command=("aws" "codepipeline" "get-pipeline-state" "--name" "$pipeline_name")
    if [[ -n "$region" ]]; then
        aws_command+=("--region" "$region")
    fi
    
    # キャッシュの存在確認（デバッグ用）- 高速化のため簡略化
    if [[ "$debug_flag" == "true" ]]; then
        echo "🔄 処理中: $pipeline_name" >&2
    fi
    
    "$AWS_CACHE_SCRIPT" "${cache_args[@]}" --batch-mode -- "${aws_command[@]}" 2>/dev/null || echo "{}"
}

# パイプラインデータを処理してソート
process_pipeline_data() {
    local pipelines_json="$1"
    local status_filter="$2"
    local cache_ttl="$3"
    local debug_flag="$4"
    local region="$5"
    local quiet_mode="$6"
    local analyze_cache="$7"
    
    # パイプライン名のリストを取得
    local pipeline_names
    pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[].name')
    
    # パイプライン総数を取得
    local total_pipelines
    total_pipelines=$(echo "$pipeline_names" | wc -l | tr -d ' ')
    
    # パイプライン数が0の場合は処理をスキップ
    if [[ $total_pipelines -eq 0 ]]; then
        echo "[]"
        return
    fi
    
    # 各パイプラインの詳細情報を取得して結合
    local enhanced_data="[]"
    local current_count=0
    
    # キャッシュ利用状況を分析
    if [[ "$analyze_cache" == "true" ]]; then
        analyze_cache_usage "$pipelines_json" "$cache_ttl" "$region"
    fi
    
    # プログレスバー開始メッセージ
    if [[ "$quiet_mode" != "true" ]]; then
        echo "📊 $total_pipelines 個のパイプライン詳細情報を取得中..." >&2
    fi
    
    # 並列処理用の一時ディレクトリ
    local temp_dir=$(mktemp -d)
    local max_parallel=10  # 同時実行数を制限
    local current_parallel=0
    
    while IFS= read -r pipeline_name; do
        if [[ -n "$pipeline_name" ]]; then
            current_count=$((current_count + 1))
            
            # プログレスバー表示
            show_progress "$current_count" "$total_pipelines" "$pipeline_name" "$quiet_mode" "PROCESSING"
            
            # 並列処理制限
            if [[ $current_parallel -ge $max_parallel ]]; then
                wait  # 全ての並列処理が完了するまで待機
                current_parallel=0
            fi
            
            # バックグラウンドで詳細情報を取得
            {
                local pipeline_state
                pipeline_state=$(get_pipeline_details "$pipeline_name" "$cache_ttl" "$debug_flag" "$region")
                
                # 基本情報と状態情報を結合
                local pipeline_info
                pipeline_info=$(echo "$pipelines_json" | jq --arg name "$pipeline_name" '.pipelines[] | select(.name == $name)')
                
                local combined_info
                combined_info=$(echo "$pipeline_info" | jq --argjson state "$pipeline_state" '. + {state: $state}')
                
                # 一時ファイルに保存
                echo "$combined_info" > "$temp_dir/${current_count}.json"
            } &
            
            current_parallel=$((current_parallel + 1))
        fi
    done <<< "$pipeline_names"
    
    # 残りの並列処理完了を待機
    wait
    
    # 一時ファイルから結果を結合
    for ((i=1; i<=total_pipelines; i++)); do
        if [[ -f "$temp_dir/${i}.json" ]]; then
            local item_data
            item_data=$(cat "$temp_dir/${i}.json")
            enhanced_data=$(echo "$enhanced_data" | jq --argjson item "$item_data" '. + [$item]')
        fi
    done
    
    # 一時ディレクトリを削除
    rm -rf "$temp_dir"
    
    # 完了メッセージ
    if [[ "$quiet_mode" != "true" ]]; then
        echo "✅ パイプライン詳細情報の取得が完了しました" >&2
    fi
    
    # ステータスフィルター適用
    local jq_filter='.'
    if [[ "$status_filter" != "ALL" ]]; then
        jq_filter="map(select(.state.stageStates[]?.latestExecution?.status == \"$status_filter\"))"
    fi
    
    # 名前でソート
    jq_filter="$jq_filter | sort_by(.name)"
    
    echo "$enhanced_data" | jq "$jq_filter"
}

# テーブル形式で出力
format_table() {
    local pipelines_json="$1"
    
    echo "🚀 AWS CodePipeline 一覧"
    echo "============================================================================================================"
    printf "%-30s %-15s %-20s %-25s %-15s\n" "Pipeline Name" "Status" "Last Execution" "Updated" "Version"
    echo "============================================================================================================"
    
    echo "$pipelines_json" | jq -r '.[] | 
        [
            .name,
            (.state.stageStates[0]?.latestExecution?.status // "Unknown"),
            (.state.stageStates[0]?.latestExecution?.lastStatusChange // "N/A" | 
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
        # ステータスに応じて色分け（簡易版）
        local status_display="$status"
        case "$status" in
            "Succeeded") status_display="✅ $status" ;;
            "Failed") status_display="❌ $status" ;;
            "InProgress") status_display="🔄 $status" ;;
            "Stopped") status_display="⏹️  $status" ;;
        esac
        
        printf "%-30s %-15s %-20s %-25s %-15s\n" \
            "${name:0:29}" \
            "${status_display:0:14}" \
            "${last_exec:0:19}" \
            "${updated:0:24}" \
            "${version:0:14}"
    done
    
    echo "============================================================================================================"
    
    # 統計情報
    local total_count succeeded_count failed_count inprogress_count
    total_count=$(echo "$pipelines_json" | jq 'length')
    succeeded_count=$(echo "$pipelines_json" | jq '[.[] | select(.state.stageStates[0]?.latestExecution?.status == "Succeeded")] | length')
    failed_count=$(echo "$pipelines_json" | jq '[.[] | select(.state.stageStates[0]?.latestExecution?.status == "Failed")] | length')
    inprogress_count=$(echo "$pipelines_json" | jq '[.[] | select(.state.stageStates[0]?.latestExecution?.status == "InProgress")] | length')
    
    echo "📊 統計: 総数=$total_count, 成功=$succeeded_count, 失敗=$failed_count, 実行中=$inprogress_count"
}

# CSV形式で出力
format_csv() {
    local pipelines_json="$1"
    
    echo "PipelineName,Status,LastExecution,Updated,Version"
    echo "$pipelines_json" | jq -r '.[] | 
        [
            .name,
            (.state.stageStates[0]?.latestExecution?.status // "Unknown"),
            (.state.stageStates[0]?.latestExecution?.lastStatusChange // "N/A" | 
                if . == "N/A" then . 
                else (. | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S"))
                end),
            (.updated // "N/A" | 
                if . == "N/A" then . 
                else (. | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S"))
                end),
            (.version // "N/A" | tostring)
        ] | @csv'
}

# JSON形式で出力（整形済み）
format_json() {
    local pipelines_json="$1"
    
    echo "$pipelines_json" | jq '.'
}

# メイン処理
main() {
    local format="table"
    local status_filter="ALL"
    local cache_ttl="1800"  # 30分（パイプライン状況は頻繁に変わらないため）
    local debug_flag="false"
    local region=""
    local quiet_mode="false"
    local analyze_cache="false"
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--format)
                format="$2"
                if [[ ! "$format" =~ ^(table|json|csv)$ ]]; then
                    echo "❌ エラー: 無効な出力形式: $format" >&2
                    echo "有効な形式: table, json, csv" >&2
                    exit 1
                fi
                shift 2
                ;;
            -s|--status)
                status_filter="$2"
                if [[ ! "$status_filter" =~ ^(ALL|Succeeded|Failed|InProgress|Stopped)$ ]]; then
                    echo "❌ エラー: 無効なステータス: $status_filter" >&2
                    echo "有効なステータス: ALL, Succeeded, Failed, InProgress, Stopped" >&2
                    exit 1
                fi
                shift 2
                ;;
            -c|--cache-ttl)
                cache_ttl="$2"
                if ! [[ "$cache_ttl" =~ ^[0-9]+$ ]]; then
                    echo "❌ エラー: TTLは数値で指定してください: $cache_ttl" >&2
                    exit 1
                fi
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet_mode="true"
                shift
                ;;
            --analyze-cache)
                analyze_cache="true"
                shift
                ;;
            -d|--debug)
                debug_flag="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "❌ エラー: 不明なオプション: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done
    
    # パイプラインデータを取得
    local pipelines_json
    pipelines_json=$(get_pipeline_data "$cache_ttl" "$debug_flag" "$region")
    
    # 結果が空の場合
    if [[ "$(echo "$pipelines_json" | jq '.pipelines | length')" == "0" ]]; then
        echo "⚠️  CodePipelineが見つかりませんでした" >&2
        exit 0
    fi
    
    # パイプラインデータを処理
    local processed_data
    processed_data=$(process_pipeline_data "$pipelines_json" "$status_filter" "$cache_ttl" "$debug_flag" "$region" "$quiet_mode" "$analyze_cache")
    
    # フィルター後の結果が空の場合
    if [[ "$(echo "$processed_data" | jq 'length')" == "0" ]]; then
        echo "⚠️  条件に一致するパイプラインが見つかりませんでした" >&2
        exit 0
    fi
    
    # 指定された形式で出力
    case $format in
        table)
            format_table "$processed_data"
            ;;
        json)
            format_json "$processed_data"
            ;;
        csv)
            format_csv "$processed_data"
            ;;
    esac
}

# スクリプトが直接実行された場合のみmainを呼び出し
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi