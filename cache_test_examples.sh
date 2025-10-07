#!/usr/bin/env bash

# AWS Cache Test機能の使用例

echo "=== AWS Cache Test機能 使用例 ==="
echo

echo "1. 基本的なキャッシュテスト"
echo "コマンド: ./aws_cache.sh --test \"aws s3api list-buckets\""
echo "説明: 指定コマンドのキャッシュ存在と有効性を確認"
echo

echo "2. 特定TTLでのテスト"
echo "コマンド: ./aws_cache.sh --test \"aws s3api list-buckets\" -t 300"
echo "説明: 5分TTLとしてキャッシュの有効性を確認"
echo

echo "3. 存在しないキャッシュのテスト"
echo "コマンド: ./aws_cache.sh --test \"aws ec2 describe-instances --region us-west-2\""
echo "説明: まだ実行していないコマンドのキャッシュ状況を確認"
echo

echo "4. 複雑なコマンドのテスト"
echo "コマンド: ./aws_cache.sh --test \"aws organizations list-accounts\""
echo "説明: 複数パラメータを含むコマンドのキャッシュ確認"
echo

echo "=== 実際のテスト実行例 ==="
echo

echo "📋 テスト1: S3バケット一覧のキャッシュ確認（簡潔モード）"
if ./aws_cache.sh --test "aws s3api list-buckets"; then
    echo "✅ キャッシュ有効"
else
    echo "❌ キャッシュ無効または存在しない"
fi

echo
echo "📋 テスト2: 詳細モード（デバッグ付き）"
./aws_cache.sh --test "aws s3api list-buckets" -d

echo
echo "📋 テスト3: 存在しないキャッシュの確認"
if ./aws_cache.sh --test "aws ec2 describe-instances --region us-west-2"; then
    echo "✅ キャッシュ有効"
else
    echo "❌ キャッシュ無効または存在しない"
fi

echo
echo "📋 テスト4: スクリプトでの条件分岐例"
COMMAND="aws s3api list-buckets"
TTL=300  # 5分

if ./aws_cache.sh --test "$COMMAND" -t $TTL >/dev/null 2>&1; then
    echo "✅ キャッシュが有効です。既存データを使用します。"
    ./aws_cache.sh -- $COMMAND
else
    echo "⚠️  キャッシュが無効または存在しません。データを更新します。"
    ./aws_cache.sh -f -- $COMMAND
fi

echo
echo "=== キャッシュ管理ワークフロー例 ==="
echo

echo "# 1. キャッシュの存在確認"
echo "./aws_cache.sh --test \"aws s3api list-buckets\""
echo

echo "# 2. キャッシュが存在しない場合は作成"
echo "if ! ./aws_cache.sh --test \"aws s3api list-buckets\" >/dev/null 2>&1; then"
echo "    echo \"キャッシュを作成中...\""
echo "    ./aws_cache.sh -- aws s3api list-buckets"
echo "fi"
echo

echo "# 3. キャッシュが期限切れの場合は更新"
echo "if ! ./aws_cache.sh --test \"aws s3api list-buckets\" -t 300 >/dev/null 2>&1; then"
echo "    echo \"キャッシュを更新中...\""
echo "    ./aws_cache.sh -f -- aws s3api list-buckets"
echo "fi"
echo

echo "# 4. キャッシュ一覧で全体状況を確認"
echo "./aws_cache.sh --list"