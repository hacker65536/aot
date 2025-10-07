#!/usr/bin/env bash

# AWS Cache使用例

echo "=== AWS CLI Cache System 使用例 ==="
echo

# 基本的な使用方法
echo "1. EC2インスタンス一覧を取得（10分キャッシュ）"
./aws_cache.sh -t 600 -- aws ec2 describe-instances --region us-east-1

echo
echo "2. S3バケット一覧を取得（デフォルトキャッシュ）"
./aws_cache.sh -- aws s3api list-buckets

echo
echo "3. 同じコマンドを再実行（キャッシュから取得）"
./aws_cache.sh -- aws s3api list-buckets

echo
echo "4. デバッグモードで実行（詳細ログ表示）"
./aws_cache.sh -d -- aws s3api list-buckets

echo
echo "5. 強制的にキャッシュを更新"
./aws_cache.sh -f -- aws s3api list-buckets

echo
echo "6. キャッシュ一覧を表示"
./aws_cache.sh --list

echo
echo "7. 特定パターンのキャッシュをクリア"
./aws_cache.sh --clear s3

echo
echo "8. 全キャッシュをクリア"
./aws_cache.sh --clear