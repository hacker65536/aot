#!/usr/bin/env bash

# パフォーマンス比較レポート

set -euo pipefail

echo "🚀 パフォーマンス比較レポート"
echo "============================================================================================================"

echo "📊 実行時間比較:"
echo

# 元のスクリプト
echo "1. 元のget_pipelines.sh:"
time_start=$(date +%s.%N)
./get_pipelines.sh -q >/dev/null 2>&1
time_end=$(date +%s.%N)
original_time=$(echo "$time_end - $time_start" | bc -l)
printf "   実行時間: %.2f秒\n" "$original_time"

echo

# 最適化版スクリプト
echo "2. 最適化版optimized_get_pipelines.sh:"
time_start=$(date +%s.%N)
./optimized_get_pipelines.sh -q >/dev/null 2>&1
time_end=$(date +%s.%N)
optimized_time=$(echo "$time_end - $time_start" | bc -l)
printf "   実行時間: %.2f秒\n" "$optimized_time"

echo
echo "============================================================================================================"
echo "📈 改善効果:"

# 改善率計算
improvement=$(echo "scale=2; $original_time - $optimized_time" | bc -l)
improvement_percent=$(echo "scale=1; $improvement * 100 / $original_time" | bc -l)
speedup=$(echo "scale=2; $original_time / $optimized_time" | bc -l)

printf "   時間短縮: %.2f秒 (%.1f%%改善)\n" "$improvement" "$improvement_percent"
printf "   高速化倍率: %.2f倍\n" "$speedup"

echo
echo "🔧 主な最適化ポイント:"
echo "   1. 結果結合処理の最適化: jq slurpを使用してファイル結合を高速化"
echo "   2. 並列処理数の増加: 10 → 15並列"
echo "   3. jqクエリの最適化: 複数回の処理を1回にまとめる"
echo "   4. 統計処理の簡略化: 複雑なgroup_byを個別カウントに変更"

echo
echo "💡 さらなる改善案:"
if (( $(echo "$optimized_time > 2" | bc -l) )); then
    echo "   - 並列処理数をさらに増加 (15 → 20-25)"
    echo "   - キャッシュTTLを長くする (30分 → 1-2時間)"
    echo "   - 必要最小限の情報のみ取得するクエリフィルターを使用"
else
    echo "   ✅ 現在の性能で十分高速です"
fi

echo
echo "============================================================================================================"
echo "📋 推奨設定:"
echo "   - 通常使用: ./optimized_get_pipelines.sh -c 3600 (1時間キャッシュ)"
echo "   - 定期実行: crontabで30分ごとにバックグラウンド実行"
echo "   - 大量データ: 並列数を20-25に増加"

echo "============================================================================================================"