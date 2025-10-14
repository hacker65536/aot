#!/usr/bin/env bash

# AWS CodePipeline 一覧取得スクリプト
# パイプラインの状態、最終実行状況などを表示
# aws_cache.sh を利用してAPIレスポンスをキャッシュし、高速化を実現

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_CACHE_SCRIPT="$SCRIPT_DIR/aws_cache.sh"
CONFIG_FILE="$SCRIPT_DIR/aot_config.conf"

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

# 設定ファイルを読み込む関数
load_config() {
    local config_file="$1"
    
    # 設定ファイルが存在しない場合はデフォルト値を使用
    if [[ ! -f "$config_file" ]]; then
        echo "⚠️  設定ファイルが見つかりません: $config_file" >&2
        echo "💡 デフォルト設定を使用します。設定ファイルを作成する場合:" >&2
        echo "   cp aot_config.example.conf aot_config.conf" >&2
        return 1
    fi
    
    # Bash変数形式の設定ファイルを読み込み
    # shellcheck source=/dev/null
    source "$config_file"
    return 0
}

# キャッシュ利用状況を分析
analyze_cache_usage() {
    local pipelines_json="$1"
    local cache_ttl="$2"
    local region="$3"
    local query_filter="$4"
    
    echo "🔍 キャッシュ分析モード - パイプライン情報を取得せずにキャッシュ状況のみを分析します" >&2
    echo "============================================================================================================" >&2
    
    local pipeline_names
    if [[ -n "$query_filter" ]]; then
        pipeline_names=$(echo "$pipelines_json" | jq -r '.[].name')
        echo "📋 フィルター適用: $query_filter" >&2
    else
        pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[].name')
    fi
    
    local total_pipelines
    total_pipelines=$(echo "$pipeline_names" | wc -l | tr -d ' ')
    
    local cache_hits=0
    local cache_misses=0
    local list_cache_status="❌ MISS"
    
    # パイプライン一覧のキャッシュ状況をチェック
    local list_command=("aws" "codepipeline" "list-pipelines")
    if [[ -n "$region" ]]; then
        list_command+=("--region" "$region")
    fi
    if [[ -n "$query_filter" ]]; then
        list_command+=("--query" "$query_filter")
    fi
    
    local list_command_str="${list_command[*]}"
    if "$AWS_CACHE_SCRIPT" --test "$list_command_str" -t "$cache_ttl" >/dev/null 2>&1; then
        list_cache_status="✅ HIT"
    fi
    
    echo "📊 キャッシュ状況分析:" >&2
    echo "   パイプライン一覧: $list_cache_status" >&2
    echo "   対象パイプライン数: $total_pipelines" >&2
    echo "   キャッシュTTL: ${cache_ttl}秒 ($((cache_ttl / 60))分)" >&2
    echo >&2
    
    echo "🔍 個別パイプライン状態のキャッシュ状況を確認中..." >&2
    
    local progress=0
    while IFS= read -r pipeline_name; do
        if [[ -n "$pipeline_name" ]]; then
            progress=$((progress + 1))
            
            # プログレスを表示（10個ごと）
            if [[ $((progress % 10)) -eq 0 ]] || [[ $progress -eq $total_pipelines ]]; then
                echo "   進捗: $progress/$total_pipelines パイプライン確認済み" >&2
            fi
            
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
    
    local hit_rate=0
    if [[ $total_pipelines -gt 0 ]]; then
        hit_rate=$((cache_hits * 100 / total_pipelines))
    fi
    
    local miss_rate=$((100 - hit_rate))
    local estimated_time_with_cache=$((cache_hits / 10 + cache_misses * 2))
    local estimated_time_without_cache=$((total_pipelines * 2))
    local time_saved=$((estimated_time_without_cache - estimated_time_with_cache))
    
    echo >&2
    echo "📊 詳細分析結果:" >&2
    echo "============================================================================================================" >&2
    echo "🎯 キャッシュ効率:" >&2
    echo "   ✅ キャッシュヒット: $cache_hits パイプライン ($hit_rate%)" >&2
    echo "   ❌ キャッシュミス:   $cache_misses パイプライン ($miss_rate%)" >&2
    echo >&2
    echo "⏱️  実行時間予測:" >&2
    echo "   キャッシュ利用時:   ${estimated_time_with_cache}秒" >&2
    echo "   キャッシュなし時:   ${estimated_time_without_cache}秒" >&2
    echo "   時間短縮効果:       ${time_saved}秒 ($((time_saved * 100 / estimated_time_without_cache))%短縮)" >&2
    echo >&2
    
    # パフォーマンス評価と推奨事項
    echo "💡 パフォーマンス評価と推奨事項:" >&2
    if [[ $hit_rate -ge 90 ]]; then
        echo "   🌟 キャッシュ効率: 非常に優秀 (${hit_rate}%)" >&2
        echo "   ✨ 現在の設定が最適です。このまま継続してください。" >&2
    elif [[ $hit_rate -ge 70 ]]; then
        echo "   ✅ キャッシュ効率: 優秀 (${hit_rate}%)" >&2
        echo "   📈 さらなる改善のため、TTLを少し長くすることを検討してください。" >&2
    elif [[ $hit_rate -ge 50 ]]; then
        echo "   ⚠️  キャッシュ効率: 普通 (${hit_rate}%)" >&2
        echo "   🔧 改善推奨事項:" >&2
        echo "      - TTLを長くする: -c $((cache_ttl * 2)) ($((cache_ttl * 2 / 60))分)" >&2
        echo "      - 定期的な事前キャッシュ作成を検討" >&2
    else
        echo "   ❌ キャッシュ効率: 低い (${hit_rate}%)" >&2
        echo "   🚨 緊急改善推奨事項:" >&2
        echo "      - TTLを大幅に長くする: -c 3600 (1時間)" >&2
        echo "      - 事前キャッシュ作成: ./get_pipelines.sh -q >/dev/null" >&2
        echo "      - 古いキャッシュクリア: ./aws_cache.sh --clear codepipeline" >&2
        echo "      - 定期実行スクリプトでのキャッシュ事前作成を検討" >&2
    fi
    
    echo >&2
    echo "🔧 キャッシュ管理コマンド:" >&2
    echo "   キャッシュクリア:     ./aws_cache.sh --clear codepipeline" >&2
    echo "   事前キャッシュ作成:   ./get_pipelines.sh -q >/dev/null" >&2
    echo "   キャッシュ状況確認:   ./aws_cache.sh --list" >&2
    echo "============================================================================================================" >&2
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
        "COMPLETED") cache_icon="✅" ;;
        *) cache_icon="⚪" ;;
    esac
    
    # 進捗表示（カーソルを行の先頭に戻して上書き）
    # 行をクリアしてから表示（前の文字が残らないように）
    # パイプライン名を固定幅（25文字）で表示
    local display_name="${pipeline_name:0:25}"
    printf "\r\033[K%s パイプライン詳細取得中 [%s] %d/%d (%d%%) - %-25s" "$cache_icon" "$bar" "$current" "$total" "$percentage" "$display_name" >&2
    
    # 完了時は改行（ただし、COMPLETEDステータスの場合は改行する）
    if [[ $current -eq $total && "$cache_status" == "COMPLETED" ]]; then
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

設定ファイル:
  aot_config.conf でデフォルト設定を変更できます。
  設定ファイルがない場合は aot_config.example.conf をコピーしてください。

オプション:
  -f, --format FORMAT   出力形式 (table|json|csv) [デフォルト: table]
  -s, --status STATUS   ステータスフィルター (ALL|Succeeded|Failed|InProgress|Stopped) [デフォルト: ALL]
                       設定ファイルのPIPELINES_DEFAULT_STATUSでデフォルト値を設定可能
  -c, --cache-ttl TTL   キャッシュ有効期限（秒） [デフォルト: 1800]
  -r, --region REGION   AWSリージョン [デフォルト: 現在の設定]
  --query QUERY        AWS CLIクエリフィルター [例: 'pipelines[?ends_with(name, \`-customizations-pipeline\`)]']
                       設定ファイルのPIPELINES_DEFAULT_QUERYでデフォルト値を設定可能
  -q, --quiet          プログレスバーを非表示
  --analyze-cache      キャッシュ利用状況を詳細分析（通常出力をスキップしてキャッシュ分析のみ実行）
  -d, --debug          デバッグモード（aws_cache.shのデバッグログも表示）
  -h, --help           このヘルプを表示

例:
  $0                           # 全パイプラインをテーブル形式で表示（30分キャッシュ）
  $0 -f json                   # JSON形式で出力
  $0 -f csv                    # CSV形式で出力
  $0 -s Failed                 # 失敗したパイプラインのみ表示
  $0 -r us-east-1             # 特定リージョンのパイプライン
  $0 --query 'pipelines[?ends_with(name, \`-customizations-pipeline\`)]'  # customizationsパイプラインのみ
  $0 -c 600 -d                # 10分キャッシュ、デバッグモード
  $0 -q                        # プログレスバー非表示で実行
  $0 --analyze-cache           # キャッシュ利用状況を詳細分析（通常出力なし）
  
設定ファイル例:
  cp aot_config.example.conf aot_config.conf
  # aot_config.conf を編集してAWSプロファイルやデフォルト設定を変更

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
    local query_filter="$4"
    local aws_profile="$5"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    local aws_command=("aws" "codepipeline" "list-pipelines")
    if [[ -n "$aws_profile" && "$aws_profile" != "default" ]]; then
        aws_command+=("--profile" "$aws_profile")
    fi
    if [[ -n "$region" ]]; then
        aws_command+=("--region" "$region")
    fi
    if [[ -n "$query_filter" ]]; then
        aws_command+=("--query" "$query_filter")
    fi
    
    # aws_cache.sh を使用してCodePipeline一覧を取得
    if [[ -n "$query_filter" ]]; then
        echo "🔍 CodePipeline一覧を取得中（クエリフィルター適用）..." >&2
    else
        echo "🔍 CodePipeline一覧を取得中..." >&2
    fi
    
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
    local aws_profile="$5"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    local aws_command=("aws" "codepipeline" "get-pipeline-state" "--name" "$pipeline_name")
    if [[ -n "$aws_profile" && "$aws_profile" != "default" ]]; then
        aws_command+=("--profile" "$aws_profile")
    fi
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
    local query_filter="$8"
    local aws_profile="$9"
    local max_parallel="${10}"
    
    # パイプライン名のリストを取得（クエリフィルター適用時は構造が異なる）
    local pipeline_names
    if [[ -n "$query_filter" ]]; then
        pipeline_names=$(echo "$pipelines_json" | jq -r '.[].name')
    else
        pipeline_names=$(echo "$pipelines_json" | jq -r '.pipelines[].name')
    fi
    
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
    local last_progress_shown=0
    

    
    # プログレスバー開始メッセージ
    if [[ "$quiet_mode" != "true" ]]; then
        echo "📊 $total_pipelines 個のパイプライン詳細情報を取得中..." >&2
    fi
    
    # 並列処理用の一時ディレクトリ
    local temp_dir=$(mktemp -d)
    # max_parallelは引数から取得（設定ファイルの値）
    local current_parallel=0
    
    while IFS= read -r pipeline_name; do
        if [[ -n "$pipeline_name" ]]; then
            current_count=$((current_count + 1))
            
            # プログレスバー表示（設定ファイルの間隔に従って表示）
            local progress_interval="${default_progress_interval:-25}"
            if [[ $((current_count % progress_interval)) -eq 0 ]]; then
                show_progress "$current_count" "$total_pipelines" "$pipeline_name" "$quiet_mode" "PROCESSING"
                last_progress_shown=$current_count
            fi
            
            # 並列処理制限
            if [[ $current_parallel -ge $max_parallel ]]; then
                wait  # 全ての並列処理が完了するまで待機
                current_parallel=0
            fi
            
            # バックグラウンドで詳細情報を取得
            {
                local pipeline_state
                local aws_command=("aws" "codepipeline" "get-pipeline-state" "--name" "$pipeline_name")
                if [[ -n "$aws_profile" && "$aws_profile" != "default" ]]; then
                    aws_command+=("--profile" "$aws_profile")
                fi
                if [[ -n "$region" ]]; then
                    aws_command+=("--region" "$region")
                fi
                
                local pipeline_state
                pipeline_state=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" --batch-mode -- "${aws_command[@]}" 2>/dev/null || echo "{}")
                
                # 基本情報と状態情報を結合
                local pipeline_info
                if [[ -n "$query_filter" ]]; then
                    pipeline_info=$(echo "$pipelines_json" | jq --arg name "$pipeline_name" '.[] | select(.name == $name)')
                else
                    pipeline_info=$(echo "$pipelines_json" | jq --arg name "$pipeline_name" '.pipelines[] | select(.name == $name)')
                fi
                
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
    
    # 最終プログレスバー表示（完了を明示）
    if [[ "$quiet_mode" != "true" ]]; then
        # 最後のプログレスバーが表示されていない場合、または完了メッセージを表示
        if [[ $last_progress_shown -lt $total_pipelines ]]; then
            show_progress "$total_pipelines" "$total_pipelines" "完了" "$quiet_mode" "COMPLETED"
        else
            # 最後のプログレスバーは表示されているが、完了メッセージで上書き
            show_progress "$total_pipelines" "$total_pipelines" "完了" "$quiet_mode" "COMPLETED"
        fi
        echo "🔄 結果を結合中..." >&2
    fi
    
    # 最適化された結果結合：jq slurpを使用
    enhanced_data=$(find "$temp_dir" -name "*.json" -exec cat {} \; | jq -s '.')
    
    # 一時ディレクトリを削除
    rm -rf "$temp_dir"
    
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
    
    # 統計情報（最適化版：簡略化）
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
    
    echo "📊 統計: 総数=$total_count, 実行中=$inprogress_count, 失敗=$failed_count, 成功=$succeeded_count"
}

# CSV形式で出力
format_csv() {
    local pipelines_json="$1"
    
    echo "PipelineName,Status,LastExecution,Updated,Version"
    echo "$pipelines_json" | jq -r '.[] | 
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
        ] | @csv'
}

# JSON形式で出力（整形済み）
format_json() {
    local pipelines_json="$1"
    
    echo "$pipelines_json" | jq '.'
}

# メイン処理
main() {
    # 設定ファイルを読み込み（デフォルト値を設定）
    local aws_profile="${AWS_PIPELINES_PROFILE:-default}"
    local default_region="${AWS_REGION:-}"
    local default_cache_ttl="${CACHE_TTL:-1800}"
    local default_format="${DISPLAY_FORMAT:-table}"
    local default_quiet="${DISPLAY_QUIET:-false}"
    local default_max_parallel="${PERFORMANCE_MAX_PARALLEL:-15}"
    local default_progress_interval="${DISPLAY_PROGRESS_INTERVAL:-25}"
    local default_query="${PIPELINES_DEFAULT_QUERY:-}"
    local default_status="${PIPELINES_DEFAULT_STATUS:-ALL}"
    
    # 設定ファイルが存在する場合は読み込み
    if load_config "$CONFIG_FILE"; then
        aws_profile="${AWS_PIPELINES_PROFILE:-$aws_profile}"
        default_region="${AWS_REGION:-$default_region}"
        default_cache_ttl="${CACHE_TTL:-$default_cache_ttl}"
        default_format="${DISPLAY_FORMAT:-$default_format}"
        default_quiet="${DISPLAY_QUIET:-$default_quiet}"
        default_max_parallel="${PERFORMANCE_MAX_PARALLEL:-$default_max_parallel}"
        default_progress_interval="${DISPLAY_PROGRESS_INTERVAL:-$default_progress_interval}"
        default_query="${PIPELINES_DEFAULT_QUERY:-$default_query}"
        default_status="${PIPELINES_DEFAULT_STATUS:-$default_status}"
    fi
    
    # 変数を初期化（設定ファイルの値またはデフォルト値）
    local format="$default_format"
    local status_filter="$default_status"
    local cache_ttl="$default_cache_ttl"
    local debug_flag="false"
    local region="$default_region"
    local quiet_mode="$default_quiet"
    local analyze_cache="false"
    local query_filter="$default_query"
    
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
            --query)
                query_filter="$2"
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
    pipelines_json=$(get_pipeline_data "$cache_ttl" "$debug_flag" "$region" "$query_filter" "$aws_profile")
    
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
    
    # キャッシュ分析モードの場合は詳細データ処理をスキップ
    if [[ "$analyze_cache" == "true" ]]; then
        analyze_cache_usage "$pipelines_json" "$cache_ttl" "$region" "$query_filter"
    else
        # パイプラインデータを処理
        local processed_data
        processed_data=$(process_pipeline_data "$pipelines_json" "$status_filter" "$cache_ttl" "$debug_flag" "$region" "$quiet_mode" "$analyze_cache" "$query_filter" "$aws_profile" "$default_max_parallel")
        
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
    fi
}

# スクリプトが直接実行された場合のみmainを呼び出し
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi