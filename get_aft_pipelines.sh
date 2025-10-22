#!/usr/bin/env bash

# AWS AFT Customizations Pipeline 一覧取得スクリプト
# AFTのカスタマイゼーションパイプライン（{account-id}-customizations-pipeline）の状態を
# アカウント情報と組み合わせて表示
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

# ヘルプ表示
show_help() {
    cat << EOF
AWS AFT Customizations Pipeline 一覧取得

使用方法:
  $0 [オプション]

このスクリプトは aws_cache.sh を利用してAPIレスポンスをキャッシュします。
AFTのカスタマイゼーションパイプライン（{account-id}-customizations-pipeline）の
状態をアカウント情報と組み合わせて表示します。

設定ファイル:
  aot_config.conf でデフォルト設定を変更できます。
  AWS_ACCOUNTS_PROFILE でAWS Organizationsアクセス用のプロファイルを設定してください。
  AWS_PIPELINES_PROFILE でCodePipelineアクセス用のプロファイルを設定してください。

オプション:
  -f, --format FORMAT   出力形式 (table|json|csv) [デフォルト: table]
  -s, --status STATUS   パイプラインステータスフィルター (ALL|Succeeded|Failed|InProgress|Stopped) [デフォルト: ALL]
  -c, --cache-ttl TTL   キャッシュ有効期限（秒） [デフォルト: 1800]
  -r, --region REGION   AWSリージョン [デフォルト: 設定ファイルまたはap-northeast-1]
  -d, --debug          デバッグモード（aws_cache.shのデバッグログも表示）
  -h, --help           このヘルプを表示

例:
  $0                           # AFTカスタマイゼーションパイプライン一覧をテーブル形式で表示
  $0 -f json                   # JSON形式で出力
  $0 -f csv                    # CSV形式で出力
  $0 -s Failed                 # 失敗したパイプラインのみ表示
  $0 -c 3600 -d               # 1時間キャッシュ、デバッグモード
  
キャッシュ関連:
  初回実行時: AWS APIを呼び出してキャッシュに保存
  2回目以降: キャッシュから高速取得（TTL期間内）
  強制更新: ./aws_cache.sh -f -- aws codepipeline list-pipelines

EOF
}

# アカウントデータを取得してソート（get_accounts.shから流用）
get_sorted_accounts() {
    local status_filter="$1"
    local cache_ttl="$2"
    local debug_flag="$3"
    local aws_profile="$4"
    local show_message="${5:-false}"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    # aws_cache.sh を使用してAWS Organizations list-accounts を実行
    if [[ "$show_message" == "true" ]]; then
        echo "🔍 AWS Organizations からアカウントリストを取得中..." >&2
    fi
    
    local aws_command=("aws" "organizations" "list-accounts")
    if [[ -n "$aws_profile" && "$aws_profile" != "default" ]]; then
        aws_command+=("--profile" "$aws_profile")
    fi
    
    local accounts_data
    if [[ "$show_message" == "true" ]]; then
        accounts_data=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" -- "${aws_command[@]}" 2> >(tee /dev/stderr))
    else
        accounts_data=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" -- "${aws_command[@]}" 2>/dev/null)
    fi
    
    # jqでフィルタリング、ソート、整形
    local jq_filter='.Accounts'
    
    # ステータスフィルター適用
    if [[ "$status_filter" != "ALL" ]]; then
        jq_filter="$jq_filter | map(select(.Status == \"$status_filter\"))"
    fi
    
    # JoinedTimestampでソート
    jq_filter="$jq_filter | sort_by(.JoinedTimestamp)"
    
    echo "$accounts_data" | jq -r "$jq_filter"
}

# AFTカスタマイゼーションパイプライン一覧を取得
get_aft_pipelines() {
    local cache_ttl="$1"
    local debug_flag="$2"
    local aws_profile="$3"
    local region="$4"
    
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
    
    # AFTカスタマイゼーションパイプラインのみを取得
    aws_command+=("--query" 'pipelines[?ends_with(name, `-customizations-pipeline`)]')
    
    echo "🔍 AFTカスタマイゼーションパイプライン一覧を取得中..." >&2
    
    local pipelines_data
    pipelines_data=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" --batch-mode -- "${aws_command[@]}")
    
    echo "$pipelines_data"
}

# パイプライン詳細情報を取得
get_pipeline_details() {
    local pipeline_name="$1"
    local cache_ttl="$2"
    local debug_flag="$3"
    local aws_profile="$4"
    local region="$5"
    
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
    
    "$AWS_CACHE_SCRIPT" "${cache_args[@]}" -- "${aws_command[@]}" 2>/dev/null
}

# パイプライン実行履歴を取得
get_pipeline_executions() {
    local pipeline_name="$1"
    local cache_ttl="$2"
    local debug_flag="$3"
    local aws_profile="$4"
    local region="$5"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    local aws_command=("aws" "codepipeline" "list-pipeline-executions" "--pipeline-name" "$pipeline_name" "--max-items" "1")
    if [[ -n "$aws_profile" && "$aws_profile" != "default" ]]; then
        aws_command+=("--profile" "$aws_profile")
    fi
    if [[ -n "$region" ]]; then
        aws_command+=("--region" "$region")
    fi
    
    "$AWS_CACHE_SCRIPT" "${cache_args[@]}" -- "${aws_command[@]}" 2>/dev/null
}

# テーブル形式で出力
format_table() {
    local combined_data="$1"
    local status_filter="$2"
    
    echo "🚀 AWS AFT Customizations Pipeline 一覧"
    echo "=============================================================================================================="
    printf "%-16s %-35s %-15s %-20s %-20s\n" "Account ID" "Account Name" "Status" "Last Execution" "Updated"
    echo "=============================================================================================================="
    
    echo "$combined_data" | jq -r --arg status_filter "$status_filter" '
        .[] | 
        select(
            if $status_filter == "ALL" then true
            else (.pipeline_status // "Unknown") == $status_filter
            end
        ) |
        [
            .account_id,
            (.account_name // "N/A"),
            (.pipeline_status // "Unknown"),
            (if .last_execution_time then (.last_execution_time | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S")) else "N/A" end),
            (if .pipeline_updated then (.pipeline_updated | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S")) else "N/A" end)
        ] | @tsv' | \
    while IFS=$'\t' read -r account_id account_name status last_execution updated; do
        # ステータスに応じた絵文字を追加
        case "$status" in
            "Succeeded") status_display="✅ $status" ;;
            "Failed") status_display="❌ $status" ;;
            "InProgress") status_display="🔄 $status" ;;
            "Stopped") status_display="⏹️  $status" ;;
            *) status_display="❓ $status" ;;
        esac
        
        printf "%-16s %-35s %-15s %-20s %-20s\n" "$account_id" "$account_name" "$status_display" "$last_execution" "$updated"
    done
    
    echo "=============================================================================================================="
    
    # 統計情報
    local total_count succeeded_count failed_count inprogress_count stopped_count unknown_count
    total_count=$(echo "$combined_data" | jq 'length')
    succeeded_count=$(echo "$combined_data" | jq 'map(select(.pipeline_status == "Succeeded")) | length')
    failed_count=$(echo "$combined_data" | jq 'map(select(.pipeline_status == "Failed")) | length')
    inprogress_count=$(echo "$combined_data" | jq 'map(select(.pipeline_status == "InProgress")) | length')
    stopped_count=$(echo "$combined_data" | jq 'map(select(.pipeline_status == "Stopped")) | length')
    unknown_count=$(echo "$combined_data" | jq 'map(select(.pipeline_status == null or .pipeline_status == "Unknown")) | length')
    
    echo "📈 統計: 総数=$total_count, ✅成功=$succeeded_count, ❌失敗=$failed_count, 🔄実行中=$inprogress_count, ⏹️停止=$stopped_count, ❓不明=$unknown_count"
}

# JSON形式で出力
format_json() {
    local combined_data="$1"
    local status_filter="$2"
    
    echo "$combined_data" | jq --arg status_filter "$status_filter" '
        map(select(
            if $status_filter == "ALL" then true
            else (.pipeline_status // "Unknown") == $status_filter
            end
        ))'
}

# CSV形式で出力
format_csv() {
    local combined_data="$1"
    local status_filter="$2"
    
    echo "Account ID,Account Name,Pipeline Status,Last Execution,Updated"
    echo "$combined_data" | jq -r --arg status_filter "$status_filter" '
        .[] | 
        select(
            if $status_filter == "ALL" then true
            else (.pipeline_status // "Unknown") == $status_filter
            end
        ) |
        [
            .account_id,
            (.account_name // "N/A"),
            (.pipeline_status // "Unknown"),
            (if .last_execution_time then (.last_execution_time | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S")) else "N/A" end),
            (if .pipeline_updated then (.pipeline_updated | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S")) else "N/A" end)
        ] | @csv'
}

# メイン処理
main() {
    # 設定ファイルを読み込み
    load_config "$CONFIG_FILE" || true
    
    # デフォルト値設定
    local format="${PIPELINES_DEFAULT_FORMAT:-table}"
    local status_filter="${PIPELINES_DEFAULT_STATUS:-ALL}"
    local cache_ttl="${CACHE_TTL:-1800}"
    local region="${AWS_DEFAULT_REGION:-ap-northeast-1}"
    local aws_accounts_profile="${AWS_ACCOUNTS_PROFILE:-default}"
    local aws_pipelines_profile="${AWS_PIPELINES_PROFILE:-default}"
    local debug_flag="false"
    
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
            -d|--debug)
                debug_flag="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "❌ エラー: 不明なオプション: $1" >&2
                show_help
                exit 1
                ;;
            *)
                echo "❌ エラー: 不明な引数: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done
    
    # アカウント情報を取得（get_accounts.shを直接呼び出し）
    local accounts_json
    accounts_json=$("$SCRIPT_DIR/get_accounts.sh" -f json -s ACTIVE -c "$cache_ttl" 2>/dev/null)
    
    # AFTパイプライン一覧を取得
    local pipelines_json
    pipelines_json=$(get_aft_pipelines "$cache_ttl" "$debug_flag" "$aws_pipelines_profile" "$region")
    
    # パイプライン数を確認
    local pipeline_count
    pipeline_count=$(echo "$pipelines_json" | jq 'length')
    
    if [[ "$debug_flag" == "true" ]]; then
        echo "🔍 デバッグ: パイプライン数 = $pipeline_count" >&2
        echo "🔍 デバッグ: パイプラインJSON = $(echo "$pipelines_json" | head -c 200)..." >&2
    fi
    
    if [[ "$pipeline_count" -eq 0 ]]; then
        echo "⚠️  AFTカスタマイゼーションパイプラインが見つかりませんでした" >&2
        exit 0
    fi
    
    echo "📊 $pipeline_count 個のAFTパイプライン詳細情報を取得中..." >&2
    
    # アカウント情報をハッシュマップ形式で準備（高速ルックアップのため）
    local accounts_lookup
    accounts_lookup=$(echo "$accounts_json" | jq -r 'map({(.Id): .Name}) | add')
    
    # パイプライン詳細情報を並列取得
    local temp_dir=$(mktemp -d)
    local max_parallel="${PERFORMANCE_MAX_PARALLEL:-10}"
    local current_parallel=0
    local processed=0
    
    local pipeline_names
    pipeline_names=$(echo "$pipelines_json" | jq -r '.[].name')
    
    while IFS= read -r pipeline_name; do
        [[ -z "$pipeline_name" ]] && continue
        
        processed=$((processed + 1))
        
        # プログレスバー表示
        if [[ $((processed % 25)) -eq 0 ]] || [[ $processed -eq $pipeline_count ]]; then
            printf "\r✅ AFTパイプライン詳細取得中 [%d/%d] (%d%%) - %s" "$processed" "$pipeline_count" "$((processed * 100 / pipeline_count))" "$pipeline_name" >&2
        fi
        
        # 並列処理制限
        if [[ $current_parallel -ge $max_parallel ]]; then
            wait  # 全ての並列処理が完了するまで待機
            current_parallel=0
        fi
        
        # バックグラウンドで詳細情報を取得
        {
            # アカウントIDを抽出
            local account_id
            account_id=$(echo "$pipeline_name" | sed 's/-customizations-pipeline$//')
            
            # アカウント名を高速ルックアップ
            local account_name
            account_name=$(echo "$accounts_lookup" | jq -r --arg account_id "$account_id" '.[$account_id] // "N/A"')
            
            # パイプライン詳細を取得
            local pipeline_state pipeline_executions
            pipeline_state=$(get_pipeline_details "$pipeline_name" "$cache_ttl" "$debug_flag" "$aws_pipelines_profile" "$region")
            pipeline_executions=$(get_pipeline_executions "$pipeline_name" "$cache_ttl" "$debug_flag" "$aws_pipelines_profile" "$region")
            
            # データを結合
            local pipeline_data
            pipeline_data=$(jq -n \
                --arg account_id "$account_id" \
                --arg account_name "$account_name" \
                --arg pipeline_name "$pipeline_name" \
                --argjson pipeline_state "$pipeline_state" \
                --argjson pipeline_executions "$pipeline_executions" \
                '{
                    account_id: $account_id,
                    account_name: $account_name,
                    pipeline_name: $pipeline_name,
                    pipeline_status: (
                        [$pipeline_state.stageStates[]?.latestExecution?.status] as $statuses |
                        if ($statuses | map(select(. == "InProgress")) | length) > 0 then "InProgress"
                        elif ($statuses | map(select(. == "Failed")) | length) > 0 then "Failed"
                        elif ($statuses | map(select(. == "Stopped")) | length) > 0 then "Stopped"
                        elif ($statuses | map(select(. == "Succeeded")) | length) == ($statuses | length) and ($statuses | length) > 0 then "Succeeded"
                        else "Unknown"
                        end
                    ),
                    pipeline_updated: ($pipeline_state.updated // null),
                    last_execution_time: ($pipeline_executions.pipelineExecutionSummaries[0].lastUpdateTime // null),
                    last_execution_status: ($pipeline_executions.pipelineExecutionSummaries[0].status // null)
                }')
            
            # 一時ファイルに保存
            echo "$pipeline_data" > "$temp_dir/${processed}.json"
        } &
        
        current_parallel=$((current_parallel + 1))
    done <<< "$pipeline_names"
    
    # 残りの並列処理完了を待機
    wait
    
    echo "" >&2
    echo "🔄 結果を結合中..." >&2
    
    # 結果を結合
    local combined_data="[]"
    if [[ -d "$temp_dir" ]]; then
        combined_data=$(find "$temp_dir" -name "*.json" -exec cat {} \; | jq -s '.')
        rm -rf "$temp_dir"
    fi
    
    echo "✅ AFTパイプライン詳細情報の取得が完了しました" >&2
    
    # 出力形式に応じて表示
    case "$format" in
        "table")
            format_table "$combined_data" "$status_filter"
            ;;
        "json")
            format_json "$combined_data" "$status_filter"
            ;;
        "csv")
            format_csv "$combined_data" "$status_filter"
            ;;
    esac
}

# スクリプトが直接実行された場合のみmainを呼び出し
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi