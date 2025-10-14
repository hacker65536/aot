#!/usr/bin/env bash

# 設定ファイル読み込みのテスト

set -euo pipefail

CONFIG_FILE="aot_config.conf"

echo "設定ファイル読み込みテスト"
echo "=========================="

# デフォルト値を設定
AWS_DEFAULT_PROFILE="default"
AWS_PIPELINES_PROFILE="default"
AWS_ACCOUNTS_PROFILE="default"
AWS_REGION=""
CACHE_TTL=1800
DISPLAY_FORMAT="table"
DISPLAY_QUIET=false
PERFORMANCE_MAX_PARALLEL=15
DISPLAY_PROGRESS_INTERVAL=25
PIPELINES_DEFAULT_QUERY=""
PIPELINES_DEFAULT_STATUS="ALL"

# 設定ファイルが存在する場合は読み込み
if [[ -f "$CONFIG_FILE" ]]; then
    echo "設定ファイル: $CONFIG_FILE を読み込み中..."
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo "設定ファイルが見つかりません: $CONFIG_FILE"
    echo "デフォルト値を使用します"
fi

echo
echo "読み込まれた設定値:"
echo "Default Profile: $AWS_DEFAULT_PROFILE"
echo "Pipelines Profile: $AWS_PIPELINES_PROFILE"
echo "Accounts Profile: $AWS_ACCOUNTS_PROFILE"
echo "AWS Region: $AWS_REGION"
echo "Cache TTL: $CACHE_TTL"
echo "Format: $DISPLAY_FORMAT"
echo "Quiet: $DISPLAY_QUIET"
echo "Max Parallel: $PERFORMANCE_MAX_PARALLEL"
echo "Progress Interval: $DISPLAY_PROGRESS_INTERVAL"
echo "Default Query: $PIPELINES_DEFAULT_QUERY"
echo "Default Status: $PIPELINES_DEFAULT_STATUS"