#!/usr/bin/env bash

# AWS Organizations アカウントリスト取得スクリプト
# 有効なアカウントをjoin日付でソートして表示
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

# ヘルプ表示
show_help() {
    cat << EOF
AWS Organizations アカウントリスト取得

使用方法:
  $0 [オプション]

このスクリプトは aws_cache.sh を利用してAPIレスポンスをキャッシュします。
同じ条件での再実行時は高速にデータを取得できます。

オプション:
  -f, --format FORMAT   出力形式 (table|json|csv) [デフォルト: table]
  -s, --status STATUS   ステータスフィルター (ACTIVE|SUSPENDED|ALL) [デフォルト: ACTIVE]
  -c, --cache-ttl TTL   キャッシュ有効期限（秒） [デフォルト: 1800]
  -d, --debug          デバッグモード（aws_cache.shのデバッグログも表示）
  -h, --help           このヘルプを表示

例:
  $0                           # 有効なアカウントをテーブル形式で表示（30分キャッシュ）
  $0 -f json                   # JSON形式で出力
  $0 -f csv                    # CSV形式で出力
  $0 -s ALL                    # 全ステータスのアカウントを表示
  $0 -c 3600 -d               # 1時間キャッシュ、デバッグモード
  
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
    
    local cache_args=("-t" "$cache_ttl")
    if [[ "$debug_flag" == "true" ]]; then
        cache_args+=("-d")
    fi
    
    # aws_cache.sh を使用してAWS Organizations list-accounts を実行
    # キャッシュがあれば高速取得、なければAPI実行してキャッシュに保存
    echo "🔍 AWS Organizations からアカウントリストを取得中（キャッシュ利用）..." >&2
    
    local accounts_data
    accounts_data=$("$AWS_CACHE_SCRIPT" "${cache_args[@]}" -- aws organizations list-accounts)
    
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

# テーブル形式で出力
format_table() {
    local accounts_json="$1"
    
    echo "📊 AWS Organizations アカウント一覧"
    echo "================================================================================================================"
    printf "%-15s %-12s %-30s %-20s %-20s\n" "Account ID" "Status" "Name" "Email" "Joined Date"
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
        printf "%-15s %-12s %-30s %-20s %-20s\n" "$id" "$status" "${name:0:29}" "${email:0:19}" "$joined"
    done
    
    echo "================================================================================================================"
    
    # 統計情報
    local total_count active_count suspended_count
    total_count=$(echo "$accounts_json" | jq 'length')
    active_count=$(echo "$accounts_json" | jq 'map(select(.Status == "ACTIVE")) | length')
    suspended_count=$(echo "$accounts_json" | jq 'map(select(.Status == "SUSPENDED")) | length')
    
    echo "📈 統計: 総数=$total_count, 有効=$active_count, 停止=$suspended_count"
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
    local format="table"
    local status_filter="ACTIVE"
    local cache_ttl="1800"  # 30分
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
    local accounts_json
    accounts_json=$(get_sorted_accounts "$status_filter" "$cache_ttl" "$debug_flag")
    
    # 結果が空の場合
    if [[ "$(echo "$accounts_json" | jq 'length')" == "0" ]]; then
        echo "⚠️  条件に一致するアカウントが見つかりませんでした" >&2
        exit 0
    fi
    
    # 指定された形式で出力
    case $format in
        table)
            format_table "$accounts_json"
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