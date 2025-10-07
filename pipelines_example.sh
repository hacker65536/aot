#!/usr/bin/env bash

# AWS CodePipeline 一覧取得の使用例

echo "=== AWS CodePipeline 一覧取得例 ==="
echo

echo "1. 基本使用（全パイプラインをテーブル形式）"
echo "コマンド: ./get_pipelines.sh"
echo

echo "2. JSON形式で出力"
echo "コマンド: ./get_pipelines.sh -f json"
echo

echo "3. CSV形式で出力"
echo "コマンド: ./get_pipelines.sh -f csv"
echo

echo "4. 失敗したパイプラインのみ表示"
echo "コマンド: ./get_pipelines.sh -s Failed"
echo

echo "5. 成功したパイプラインのみ表示"
echo "コマンド: ./get_pipelines.sh -s Succeeded"
echo

echo "6. 実行中のパイプラインのみ表示"
echo "コマンド: ./get_pipelines.sh -s InProgress"
echo

echo "7. 特定リージョンのパイプライン"
echo "コマンド: ./get_pipelines.sh -r us-east-1"
echo

echo "8. キャッシュ10分、デバッグモード"
echo "コマンド: ./get_pipelines.sh -c 600 -d"
echo

echo "9. プログレスバー非表示で実行"
echo "コマンド: ./get_pipelines.sh -q"
echo

echo "10. CSV形式でファイルに保存"
echo "コマンド: ./get_pipelines.sh -f csv > pipelines.csv"
echo

echo "11. jqと組み合わせて特定の情報のみ抽出（プログレスバー非表示）"
echo "コマンド: ./get_pipelines.sh -q -f json | jq '.[] | {name: .name, status: .state.stageStates[0]?.latestExecution?.status}'"
echo

echo "12. 失敗したパイプラインの詳細情報"
echo "コマンド: ./get_pipelines.sh -s Failed -f json | jq '.[] | {name: .name, failureDetails: .state.stageStates[].actionStates[]?.latestExecution?.errorDetails}'"
echo

echo "13. パイプライン実行履歴の確認"
echo "コマンド: ./get_pipelines.sh -f json | jq '.[] | select(.name == \"my-pipeline\") | .state.stageStates[].latestExecution'"
echo

echo "=== 実際の実行例 ==="
echo

# 実際にコマンドを実行（コメントアウト状態）
# echo "🚀 CodePipeline一覧（テーブル形式）:"
# ./get_pipelines.sh

# echo
# echo "📄 JSON形式での出力:"
# ./get_pipelines.sh -f json | head -30

echo "上記のコメントアウトを外すと実際に実行されます"