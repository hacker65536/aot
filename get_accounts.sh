#!/usr/bin/env bash

# AWS Organizations アカウントリスト取得スクリプト
# 有効なアカウントをjoin日付でソートして表示
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
AWS Organizations アカウントリスト取得

使用方法:
  $0 [オプション]

このスクリプトは aws_cache.sh を利用してAPIレスポンスをキャッシュします。
同じ条件での再実行時は高速にデータを取得できます。

設定ファイル:
  pipeline_config.conf でデフォルト設定を変更できます。
  AWS_ACCOUNTS_PROFILE でAWS Organizationsアクセス用のプロファイルを設定してください。

オプション:
  -f, --format FORMAT   出力形式 (table|json|csv) [デフォルト: table]
  -s, --status STATUS   ステータスフィルター (ACTIVE|SUSPENDED|ALL) [デフォルト: ACTIVE]
  -c, --cache-ttl TTL   キャッシュ有効期限（秒） [デフォルト: 1800]
  --filter PATTERN     アカウント名またはIDでフィルタリング（部分一致）
  --detailed           詳細表示（Status、Email列も表示）
  -d, --debug          デバッグモード（aws_cache.shのデバッグログも表示）
  -h, --help           このヘルプを表示

例:
  $0                           # 有効なアカウントをテーブル形式で表示（30分キャッシュ）
  $0 -f json                   # JSON形式で出力
  $0 -f csv                    # CSV形式で出力
  $0 -s ALL                    # 全ステータスのアカウントを表示
  $0 -c 3600 -d               # 1時間キャッシュ、デバッグモード
  
フィルタリング例:
  $0 --filter sandbox          # 名前に"sandbox"を含むアカウント
  $0 --filter 123456789012     # 特定のアカウントID（部分一致）
  $0 --filter prod             # 名前に"prod"を含むアカウント
  $0 --filter freee -s ALL     # 名前に"freee"を含む全ステータスのアカウント
  $0 --detailed               # Status、Email列も含む詳細表示
  $0 --filter sandbox --detailed  # sandboxアカウントの詳細表示
  
キャッシュ関連:
  初回実行時: AWS APIを呼び出してキャッシュに保存
  2回目以降: キャッシュから高速取得（TTL期間内）
  強制更新: ./aws_cache.sh -f -- aws organizations list-accounts

EOF
}

# アカウントデータを取得してソート
get_sorted_accounts() {
    local status_filter="$1"
    local cache_ttl="$2"
    local debug_flag="$3"
    local aws_profile="$4"
    local show_message="${5:-true}"
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    # aws_cache.sh を使用してAWS Organizations list-accounts を実行
    # キャッシュがあれば高速取得、なければAPI実行してキャッシュに保存
    if [[ "$show_message" == "true" ]]; then
        echo "🔍 AWS Organizations からアカウントリストを取得中（キャッシュ利用）..." >&2
    fi
    
    local aws_command=("aws" "organizations" "list-accounts")
    if [[ -n "$aws_profile" && "$aws_profile" != "default" ]]; then
        aws_command+=("--profile" "$aws_profile")
    fi
    
    local accounts_data
    accounts_data=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" -- "${aws_command[@]}")
    
    # jqでフィルタリング、ソート、整形
    local jq_filter='.Accounts'
    
    # ステータスフィルター適用
    if [[ "$status_filter" != "ALL" ]]; then
        jq_filter="$jq_filter | map(select(.Status == \"$status_filter\"))"
    fi
    
    # JoinedTimestamp でソート（昇順）
    jq_filter="$jq_filter | sort_by(.JoinedTimestamp)"
    
    echo "$accounts_data" | jq "$jq_filter"
}

# アカウントデータにフィルターを適用
apply_account_filters() {
    local accounts_json="$1"
    local filter_pattern="$2"
    
    local filtered_data="$accounts_json"
    
    # フィルター（名前またはIDに部分一致）
    if [[ -n "$filter_pattern" ]]; then
        filtered_data=$(echo "$filtered_data" | jq --arg pattern "$filter_pattern" '
            map(select(
                (.Name // "" | ascii_downcase | contains($pattern | ascii_downcase)) or
                (.Id | contains($pattern))
            ))
        ')
    fi
    
    echo "$filtered_data"
}

# テーブル形式で出力
format_table() {
    local accounts_json="$1"
    local all_accounts_json="$2"
    local detailed_mode="$3"
    
    echo "📊 AWS Organizations アカウント一覧"
    
    if [[ "$detailed_mode" == "true" ]]; then
        # 詳細表示モード（Status、Email列も表示）
        echo "================================================================================================================"
        printf "%-15s %-12s %-40s %-20s %-20s\n" "Account ID" "Status" "Name" "Email" "Joined Date"
        echo "================================================================================================================"
        
        echo "$accounts_json" | jq -r '.[] | 
            [
                .Id,
                .Status,
                (.Name // "N/A"),
                (.Email // "N/A"),
                (.JoinedTimestamp | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S"))
            ] | @tsv' | \
        while IFS=$'\t' read -r id status name email joined; do
            printf "%-15s %-12s %-40s %-20s %-20s\n" "$id" "$status" "$name" "${email:0:19}" "$joined"
        done
        echo "================================================================================================================"
    else
        # シンプル表示モード（Account ID、Name、Joined Dateのみ）
        echo "=============================================================================="
        printf "%-15s %-50s %-20s\n" "Account ID" "Name" "Joined Date"
        echo "=============================================================================="
        
        echo "$accounts_json" | jq -r '.[] | 
            [
                .Id,
                (.Name // "N/A"),
                (.JoinedTimestamp | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S"))
            ] | @tsv' | \
        while IFS=$'\t' read -r id name joined; do
            printf "%-15s %-50s %-20s\n" "$id" "$name" "$joined"
        done
        echo "=============================================================================="
    fi
    
    echo "=============================================================================="
    
    # 統計情報（全データから計算）
    local displayed_count total_count active_count suspended_count
    displayed_count=$(echo "$accounts_json" | jq 'length')
    
    # 全データから正しい統計を計算
    if [[ -n "$all_accounts_json" ]]; then
        total_count=$(echo "$all_accounts_json" | jq 'length')
        active_count=$(echo "$all_accounts_json" | jq 'map(select(.Status == "ACTIVE")) | length')
        suspended_count=$(echo "$all_accounts_json" | jq 'map(select(.Status == "SUSPENDED")) | length')
    else
        # フォールバック：表示データから計算
        total_count=$displayed_count
        active_count=$(echo "$accounts_json" | jq 'map(select(.Status == "ACTIVE")) | length')
        suspended_count=$(echo "$accounts_json" | jq 'map(select(.Status == "SUSPENDED")) | length')
    fi
    
    echo "📈 統計: 表示=$displayed_count, 総数=$total_count, 有効=$active_count, 停止=$suspended_count"
}

# CSV形式で出力
format_csv() {
    local accounts_json="$1"
    
    echo "AccountId,Status,Name,Email,JoinedDate"
    echo "$accounts_json" | jq -r '.[] | 
        [
            .Id,
            .Status,
            (.Name // ""),
            (.Email // ""),
            (.JoinedTimestamp | sub("\\.[0-9]+\\+.*$"; "Z") | sub("\\+.*$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y/%m/%d %H:%M:%S"))
        ] | @csv'
}

# JSON形式で出力（整形済み）
format_json() {
    local accounts_json="$1"
    
    echo "$accounts_json" | jq '.'
}

# メイン処理
main() {
    # 設定ファイルを読み込み（デフォルト値を設定）
    local aws_profile="${AWS_ACCOUNTS_PROFILE:-default}"
    local default_cache_ttl="${CACHE_TTL:-1800}"
    local default_format="${DISPLAY_FORMAT:-table}"
    
    # 設定ファイルが存在する場合は読み込み
    if load_config "$CONFIG_FILE"; then
        aws_profile="${AWS_ACCOUNTS_PROFILE:-$aws_profile}"
        default_cache_ttl="${CACHE_TTL:-$default_cache_ttl}"
        default_format="${DISPLAY_FORMAT:-$default_format}"
    fi
    
    # 変数を初期化（設定ファイルの値またはデフォルト値）
    local format="$default_format"
    local status_filter="ACTIVE"
    local cache_ttl="$default_cache_ttl"
    local debug_flag="false"
    local filter_pattern=""
    local detailed_mode="false"
    
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
                if [[ ! "$status_filter" =~ ^(ACTIVE|SUSPENDED|ALL)$ ]]; then
                    echo "❌ エラー: 無効なステータス: $status_filter" >&2
                    echo "有効なステータス: ACTIVE, SUSPENDED, ALL" >&2
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
            --filter)
                filter_pattern="$2"
                shift 2
                ;;
            --detailed)
                detailed_mode="true"
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
    
    # アカウントデータを取得
    local accounts_json all_accounts_json
    accounts_json=$(get_sorted_accounts "$status_filter" "$cache_ttl" "$debug_flag" "$aws_profile")
    
    # 統計情報用に全データも取得（ALLの場合は重複を避ける）
    if [[ "$status_filter" == "ALL" ]]; then
        all_accounts_json="$accounts_json"
    else
        # 2回目の呼び出しはメッセージを表示しない
        all_accounts_json=$(get_sorted_accounts "ALL" "$cache_ttl" "$debug_flag" "$aws_profile" "false")
    fi
    
    # フィルターを適用
    if [[ -n "$filter_pattern" ]]; then
        accounts_json=$(apply_account_filters "$accounts_json" "$filter_pattern")
    fi
    
    # 結果が空の場合
    if [[ "$(echo "$accounts_json" | jq 'length')" == "0" ]]; then
        echo "⚠️  条件に一致するアカウントが見つかりませんでした" >&2
        exit 0
    fi
    
    # 指定された形式で出力
    case $format in
        table)
            format_table "$accounts_json" "$all_accounts_json" "$detailed_mode"
            ;;
        json)
            format_json "$accounts_json"
            ;;
        csv)
            format_csv "$accounts_json"
            ;;
    esac
}

# スクリプトが直接実行された場合のみmainを呼び出し
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi