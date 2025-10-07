#!/usr/bin/env bash

# AWS Organizations アカウントリスト取得の使用例

echo "=== AWS Organizations アカウントリスト取得例 ==="
echo

echo "1. 基本使用（有効なアカウントをテーブル形式）"
echo "コマンド: ./get_accounts.sh"
echo

echo "2. JSON形式で出力"
echo "コマンド: ./get_accounts.sh -f json"
echo

echo "3. CSV形式で出力"
echo "コマンド: ./get_accounts.sh -f csv"
echo

echo "4. 全ステータスのアカウントを表示"
echo "コマンド: ./get_accounts.sh -s ALL"
echo

echo "5. 停止中のアカウントのみ表示"
echo "コマンド: ./get_accounts.sh -s SUSPENDED"
echo

echo "6. キャッシュ1時間、デバッグモード"
echo "コマンド: ./get_accounts.sh -c 3600 -d"
echo

echo "7. CSV形式でファイルに保存"
echo "コマンド: ./get_accounts.sh -f csv > accounts.csv"
echo

echo "8. jqと組み合わせて特定の情報のみ抽出"
echo "コマンド: ./get_accounts.sh -f json | jq '.[] | {id: .Id, name: .Name, email: .Email}'"
echo

echo "=== 実際の実行例 ==="
echo

# 実際にコマンドを実行（コメントアウト状態）
# echo "📊 有効なアカウント一覧（テーブル形式）:"
# ./get_accounts.sh

# echo
# echo "📄 JSON形式での出力:"
# ./get_accounts.sh -f json | head -20

echo "上記のコメントアウトを外すと実際に実行されます"