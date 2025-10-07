#!/usr/bin/env bash

# get_pipelines.shの実行をトレースして詳細な時間を測定

set -euo pipefail

echo "🔍 get_pipelines.sh実行トレース"
echo "============================================================================================================"

# bashのxtrace機能を使って実行をトレース
echo "実行開始時刻: $(date)"
echo

# 時間測定付きでスクリプトを実行
echo "📊 詳細実行ログ:"
time bash -x ./get_pipelines.sh -q 2>&1 | while IFS= read -r line; do
    echo "[$(date '+%H:%M:%S.%3N')] $line"
done

echo
echo "実行終了時刻: $(date)"