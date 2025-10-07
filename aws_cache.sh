#!/usr/bin/env bash

# AWS CLI Cache System
# AWS CLIのAPIコールレスポンスをローカルにキャッシュして再利用するシステム

# 設定
CACHE_DIR="${AWS_CACHE_DIR:-./aws_cache}"
DEFAULT_TTL="${AWS_CACHE_TTL:-3600}"  # デフォルト1時間
DEBUG_MODE=false

# キャッシュディレクトリを作成
mkdir -p "$CACHE_DIR"

# デバッグログ出力関数
debug_log() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "$@" >&2
    fi
}

# ヘルプ表示
show_help() {
    cat << EOF
AWS CLI Cache System

使用方法:
  $0 [オプション] -- <aws-cli-command>

オプション:
  -t, --ttl SECONDS     キャッシュの有効期限（秒）[デフォルト: $DEFAULT_TTL]
  -f, --force          強制的にキャッシュを更新
  -l, --list           キャッシュ一覧を表示
  -c, --clear [PATTERN] キャッシュをクリア（パターン指定可能）
  --test COMMAND       指定コマンドのキャッシュ存在・有効性をテスト
  --batch-mode         バッチ処理モード（AWS設定取得を最適化）
  -d, --debug          デバッグモード（詳細ログを表示）
  -h, --help           このヘルプを表示

例:
  $0 -- aws ec2 describe-instances
  $0 -t 600 -- aws s3api list-buckets
  $0 -f -- aws iam list-users
  $0 -d -- aws ec2 describe-instances  # デバッグモード
  $0 --batch-mode -- aws s3api list-buckets  # バッチ処理モード
  $0 --list
  $0 --clear ec2
  $0 --test "aws s3api list-buckets"   # キャッシュ存在確認

EOF
}

# AWS設定情報キャッシュファイル
AWS_CONTEXT_CACHE_FILE="$CACHE_DIR/.aws_context_cache"

# AWS設定情報を取得（キャッシュ機能付き）
get_aws_context() {
    # キャッシュファイルが存在し、5分以内に作成されている場合はキャッシュを使用
    if [[ -f "$AWS_CONTEXT_CACHE_FILE" ]]; then
        local cache_time
        if [[ "$OSTYPE" == "darwin"* ]]; then
            cache_time=$(stat -f %m "$AWS_CONTEXT_CACHE_FILE")
        else
            cache_time=$(stat -c %Y "$AWS_CONTEXT_CACHE_FILE")
        fi
        
        local current_time=$(date +%s)
        local cache_age=$((current_time - cache_time))
        
        # 5分以内のキャッシュは有効
        if [[ $cache_age -lt 300 ]]; then
            cat "$AWS_CONTEXT_CACHE_FILE"
            return
        fi
    fi
    
    # AWS設定情報を取得
    local aws_profile="${AWS_PROFILE:-default}"
    local aws_region="$AWS_REGION"
    
    # AWS_REGIONが設定されていない場合、aws configure から取得
    if [[ -z "$aws_region" ]]; then
        aws_region=$(aws configure get region 2>/dev/null || echo "")
    fi
    
    local aws_context="${aws_profile}:${aws_region}"
    
    # キャッシュファイルに保存
    echo "$aws_context" > "$AWS_CONTEXT_CACHE_FILE"
    
    echo "$aws_context"
}

# バッチモード用のAWS設定キャッシュ
BATCH_AWS_CONTEXT=""

# キャッシュキーを生成（コマンド + AWS設定のMD5ハッシュ）
generate_cache_key() {
    local command="$*"
    local aws_context
    
    # バッチモードの場合、AWS設定を一度だけ取得
    if [[ "$batch_mode" == "true" ]]; then
        if [[ -z "$BATCH_AWS_CONTEXT" ]]; then
            BATCH_AWS_CONTEXT=$(get_aws_context)
            debug_log "🔑 バッチモード: AWS設定を初回取得='$BATCH_AWS_CONTEXT'"
        fi
        aws_context="$BATCH_AWS_CONTEXT"
    else
        aws_context=$(get_aws_context)
    fi
    
    local cache_input="${command}|${aws_context}"
    
    debug_log "🔑 キャッシュキー生成: コマンド='$command', AWS設定='$aws_context'"
    
    echo -n "$cache_input" | md5 -q 2>/dev/null || echo -n "$cache_input" | md5sum | cut -d' ' -f1
}

# キャッシュファイルのパスを取得
get_cache_file() {
    local cache_key="$1"
    echo "$CACHE_DIR/${cache_key}.json"
}

# キャッシュが有効かチェック
is_cache_valid() {
    local cache_file="$1"
    local ttl="$2"
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    local cache_time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        cache_time=$(stat -f %m "$cache_file")
    else
        # Linux
        cache_time=$(stat -c %Y "$cache_file")
    fi
    
    local current_time=$(date +%s)
    local expiry_time=$((cache_time + ttl))
    
    [[ $current_time -lt $expiry_time ]]
}

# AWS CLIコマンドを実行してキャッシュ
execute_aws_command() {
    local ttl="$1"
    local force_refresh="$2"
    local batch_mode_param="$3"
    shift 3
    local aws_command=("$@")
    
    # バッチモードフラグを設定
    batch_mode="$batch_mode_param"
    
    # キャッシュキーとファイルパスを生成
    local cache_key
    cache_key=$(generate_cache_key "${aws_command[@]}")
    local cache_file
    cache_file=$(get_cache_file "$cache_key")
    
    # キャッシュが有効で強制更新でない場合
    if [[ "$force_refresh" != "true" ]] && is_cache_valid "$cache_file" "$ttl"; then
        debug_log "📦 キャッシュから取得: ${aws_command[*]}"
        # キャッシュファイルからレスポンス部分のみを抽出（カラー出力なし）
        jq -M '.response' "$cache_file"
        return 0
    fi
    
    # AWS CLIコマンドを実行
    debug_log "🔄 AWS APIを実行: ${aws_command[*]}"
    
    # --output json を自動追加（まだ指定されていない場合）
    local has_output=false
    for arg in "${aws_command[@]}"; do
        if [[ "$arg" == "--output" ]]; then
            has_output=true
            break
        fi
    done
    
    if [[ "$has_output" == "false" ]]; then
        aws_command+=(--output json)
    fi
    
    # AWS CLIを実行
    local response
    if response=$("${aws_command[@]}" 2>/dev/null); then
        # レスポンスをキャッシュに保存
        local aws_context
        aws_context=$(get_aws_context)
        local cache_data
        cache_data=$(cat << EOF
{
  "command": $(printf '%s\n' "${aws_command[@]}" | jq -R . | jq -s .),
  "aws_context": "$aws_context",
  "response": $response,
  "timestamp": "$(date -Iseconds)",
  "ttl": $ttl
}
EOF
)
        echo "$cache_data" > "$cache_file"
        debug_log "💾 レスポンスをキャッシュに保存: $cache_file"
        
        # レスポンスデータのみを出力
        echo "$response"
    else
        echo "❌ AWS CLIコマンドエラー" >&2
        return 1
    fi
}

# キャッシュ一覧を表示
list_cache() {
    echo "📋 キャッシュ一覧:"
    
    if [[ ! -d "$CACHE_DIR" ]] || [[ -z "$(ls -A "$CACHE_DIR"/*.json 2>/dev/null)" ]]; then
        echo "  キャッシュファイルがありません"
        return
    fi
    
    for cache_file in "$CACHE_DIR"/*.json; do
        if [[ -f "$cache_file" ]]; then
            local command_str
            local timestamp
            local ttl
            
            command_str=$(jq -r '.command | join(" ")' "$cache_file" 2>/dev/null)
            aws_context=$(jq -r '.aws_context // "unknown"' "$cache_file" 2>/dev/null)
            timestamp=$(jq -r '.timestamp' "$cache_file" 2>/dev/null)
            ttl=$(jq -r '.ttl' "$cache_file" 2>/dev/null)
            
            if [[ "$command_str" != "null" ]]; then
                local status="期限切れ"
                if is_cache_valid "$cache_file" "$ttl"; then
                    status="有効"
                fi
                
                # タイムスタンプを読みやすい形式に変換
                local formatted_time=""
                if [[ "$timestamp" != "null" && -n "$timestamp" ]]; then
                    # ISO形式の日時を読みやすい形式に変換
                    if command -v date >/dev/null 2>&1; then
                        if [[ "$OSTYPE" == "darwin"* ]]; then
                            # macOS
                            formatted_time=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%+*}" "+%Y/%m/%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
                        else
                            # Linux
                            formatted_time=$(date -d "$timestamp" "+%Y/%m/%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
                        fi
                    else
                        formatted_time="$timestamp"
                    fi
                else
                    formatted_time="不明"
                fi
                
                echo "  $(basename "$cache_file"): $command_str [$aws_context] ($status, $formatted_time)"
            fi
        fi
    done
}

# キャッシュをクリア
clear_cache() {
    local pattern="$1"
    
    if [[ -n "$pattern" ]]; then
        debug_log "🗑️  パターン '$pattern' にマッチするキャッシュを削除中..."
        
        local deleted_count=0
        
        # パターンマッチング方式を選択
        if [[ "$pattern" =~ ^[a-f0-9]{32}$ ]]; then
            # MD5ハッシュの場合：ファイル名で直接マッチング
            find "$CACHE_DIR" -name "*${pattern}*.json" -type f -delete
            deleted_count=$(find "$CACHE_DIR" -name "*${pattern}*.json" -type f | wc -l)
        else
            # コマンド内容でマッチング：キャッシュファイルの中身を検索
            for cache_file in "$CACHE_DIR"/*.json; do
                if [[ -f "$cache_file" ]]; then
                    # jqでコマンド内容を確認
                    local command_str
                    command_str=$(jq -r '.command | join(" ")' "$cache_file" 2>/dev/null || echo "")
                    
                    # パターンがコマンド内容に含まれているかチェック
                    if [[ "$command_str" == *"$pattern"* ]]; then
                        debug_log "🗑️  削除: $cache_file (コマンド: $command_str)"
                        rm -f "$cache_file"
                        deleted_count=$((deleted_count + 1))
                    fi
                fi
            done
        fi
        
        debug_log "✅ $deleted_count 個のキャッシュファイルを削除しました"
    else
        debug_log "🗑️  全キャッシュを削除中..."
        local total_files
        total_files=$(find "$CACHE_DIR" -name "*.json" -type f | wc -l)
        rm -f "$CACHE_DIR"/*.json
        # AWS設定キャッシュも削除
        rm -f "$AWS_CONTEXT_CACHE_FILE"
        debug_log "✅ $total_files 個のキャッシュファイルを削除しました"
    fi
}

# キャッシュの存在と有効性をテスト
test_cache() {
    local test_command="$1"
    local ttl="$2"
    
    # キャッシュキーとファイルパスを生成
    local cache_key
    cache_key=$(generate_cache_key "$test_command")
    local cache_file
    cache_file=$(get_cache_file "$cache_key")
    
    # デバッグモード時のみ詳細表示
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "🔍 キャッシュテスト結果" >&2
        echo "================================================" >&2
        echo "コマンド: $test_command" >&2
        echo "キャッシュキー: $cache_key" >&2
        echo "キャッシュファイル: $cache_file" >&2
        echo "================================================" >&2
    fi
    
    # キャッシュファイルの存在確認
    if [[ ! -f "$cache_file" ]]; then
        if [[ "$DEBUG_MODE" == "true" ]]; then
            echo "❌ キャッシュ: 存在しません" >&2
            echo "💡 ヒント: 以下のコマンドでキャッシュを作成できます" >&2
            echo "   $0 -- $test_command" >&2
        fi
        return 1
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "✅ キャッシュ: 存在します" >&2
    fi
    
    # キャッシュファイルの詳細情報を取得
    local cache_time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        cache_time=$(stat -f %m "$cache_file")
    else
        # Linux
        cache_time=$(stat -c %Y "$cache_file")
    fi
    
    local current_time=$(date +%s)
    local cache_age=$((current_time - cache_time))
    local expiry_time=$((cache_time + ttl))
    local remaining_time=$((expiry_time - current_time))
    
    # TTL有効性チェック
    if [[ $remaining_time -gt 0 ]]; then
        # デバッグモード時のみ詳細表示
        if [[ "$DEBUG_MODE" == "true" ]]; then
            # 人間が読みやすい時間形式に変換
            local cache_date
            if [[ "$OSTYPE" == "darwin"* ]]; then
                cache_date=$(date -r "$cache_time" "+%Y/%m/%d %H:%M:%S")
            else
                cache_date=$(date -d "@$cache_time" "+%Y/%m/%d %H:%M:%S")
            fi
            
            echo "📅 作成日時: $cache_date" >&2
            echo "⏱️  経過時間: ${cache_age}秒" >&2
            echo "⏳ TTL設定: ${ttl}秒" >&2
            echo "✅ TTL状態: 有効（残り${remaining_time}秒）" >&2
            
            # 残り時間を人間が読みやすい形式で表示
            local hours=$((remaining_time / 3600))
            local minutes=$(((remaining_time % 3600) / 60))
            local seconds=$((remaining_time % 60))
            
            if [[ $hours -gt 0 ]]; then
                echo "📊 残り時間: ${hours}時間${minutes}分${seconds}秒" >&2
            elif [[ $minutes -gt 0 ]]; then
                echo "📊 残り時間: ${minutes}分${seconds}秒" >&2
            else
                echo "📊 残り時間: ${seconds}秒" >&2
            fi
            
            # キャッシュファイルの内容情報
            if command -v jq >/dev/null 2>&1; then
                local cached_command
                local cached_timestamp
                local cached_ttl
                local aws_context
                
                cached_command=$(jq -r '.command | join(" ")' "$cache_file" 2>/dev/null || echo "不明")
                cached_timestamp=$(jq -r '.timestamp' "$cache_file" 2>/dev/null || echo "不明")
                cached_ttl=$(jq -r '.ttl' "$cache_file" 2>/dev/null || echo "不明")
                aws_context=$(jq -r '.aws_context // "不明"' "$cache_file" 2>/dev/null)
                
                echo "================================================" >&2
                echo "📋 キャッシュ内容詳細:" >&2
                echo "   実行コマンド: $cached_command" >&2
                echo "   AWS設定: $aws_context" >&2
                echo "   タイムスタンプ: $cached_timestamp" >&2
                echo "   保存時TTL: ${cached_ttl}秒" >&2
            fi
        fi
        
        return 0
    else
        if [[ "$DEBUG_MODE" == "true" ]]; then
            # 人間が読みやすい時間形式に変換
            local cache_date
            if [[ "$OSTYPE" == "darwin"* ]]; then
                cache_date=$(date -r "$cache_time" "+%Y/%m/%d %H:%M:%S")
            else
                cache_date=$(date -d "@$cache_time" "+%Y/%m/%d %H:%M:%S")
            fi
            
            echo "📅 作成日時: $cache_date" >&2
            echo "⏱️  経過時間: ${cache_age}秒" >&2
            echo "⏳ TTL設定: ${ttl}秒" >&2
            echo "❌ TTL状態: 期限切れ（${remaining_time#-}秒前に期限切れ）" >&2
            echo "💡 ヒント: 以下のコマンドでキャッシュを更新できます" >&2
            echo "   $0 -f -- $test_command" >&2
        fi
        return 1
    fi
}

# メイン処理
main() {
    local ttl="$DEFAULT_TTL"
    local force_refresh="false"
    local aws_command=()
    local action="execute"
    local clear_pattern=""
    local test_command=""
    local batch_mode="false"
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--ttl)
                ttl="$2"
                shift 2
                ;;
            -f|--force)
                force_refresh="true"
                shift
                ;;
            -d|--debug)
                DEBUG_MODE="true"
                shift
                ;;
            --test)
                action="test"
                test_command="$2"
                shift 2
                ;;
            --batch-mode)
                batch_mode="true"
                shift
                ;;
            -l|--list)
                action="list"
                shift
                ;;
            -c|--clear)
                action="clear"
                if [[ -n "$2" && "$2" != -* ]]; then
                    clear_pattern="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --)
                shift
                aws_command=("$@")
                break
                ;;
            *)
                echo "❌ 不明なオプション: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done
    
    # アクションを実行
    case $action in
        execute)
            if [[ ${#aws_command[@]} -eq 0 ]]; then
                echo "❌ AWS CLIコマンドが指定されていません" >&2
                show_help
                exit 1
            fi
            execute_aws_command "$ttl" "$force_refresh" "$batch_mode" "${aws_command[@]}"
            ;;
        test)
            if [[ -z "$test_command" ]]; then
                echo "❌ テスト対象のコマンドが指定されていません" >&2
                show_help
                exit 1
            fi
            test_cache "$test_command" "$ttl"
            ;;
        list)
            list_cache
            ;;
        clear)
            clear_cache "$clear_pattern"
            ;;
    esac
}

# スクリプトが直接実行された場合のみmainを呼び出し
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi