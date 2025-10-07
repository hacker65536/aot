# AFT Operations Toolkit - Documentation

このディレクトリには、AFT Operations Toolkit の詳細ドキュメントが含まれています。

## 📚 ドキュメント一覧

### 🚀 メインドキュメント

#### [README_pipelines.md](README_pipelines.md)
- `get_pipelines.sh`の詳細な使用方法
- 出力形式、フィルタリング、キャッシュ機能の説明
- 実用的な使用例とベストプラクティス

#### [README_accounts.md](README_accounts.md)
- `get_accounts.sh`の使用方法
- アカウント情報取得とフィルタリング機能
- 組織管理での活用方法

### 🔧 機能詳細ドキュメント

#### [query_filter_feature.md](query_filter_feature.md)
- `--query`オプションの詳細説明
- JMESPathクエリパターンの実用例
- 高度なフィルタリング技法

#### [cache_analysis_improvement.md](cache_analysis_improvement.md)
- `--analyze-cache`オプションの改善内容
- キャッシュ効率分析の詳細
- パフォーマンス最適化ガイド

#### [aws_cache_clear_guide.md](aws_cache_clear_guide.md)
- キャッシュクリア機能の使用方法
- キャッシュ管理のベストプラクティス
- トラブルシューティング

### 📊 技術分析ドキュメント

#### [performance_optimization_summary.md](performance_optimization_summary.md)
- パフォーマンス最適化の全体的な改善内容
- 実行時間短縮の効果測定
- 大規模環境での運用指針

#### [pipeline_status_logic_update.md](pipeline_status_logic_update.md)
- パイプライン状態判定ロジックの改善
- ステータス表示の正確性向上
- エラーハンドリングの強化

#### [statistics_fix_analysis.md](statistics_fix_analysis.md)
- 統計情報計算の修正内容
- データ精度の向上
- 集計ロジックの改善

#### [last_execution_fix_analysis.md](last_execution_fix_analysis.md)
- 最終実行時刻表示の修正
- タイムゾーン処理の改善
- 日時フォーマットの統一

### 🔄 システム設計ドキュメント

#### [cache_flow_diagram.md](cache_flow_diagram.md)
- キャッシュシステムのフロー図
- データ取得プロセスの可視化
- アーキテクチャ概要

#### [spec.md](spec.md)
- システム仕様書
- 要件定義と設計方針
- 実装ガイドライン

## 🗂️ ドキュメント分類

### 📖 ユーザーガイド
- [README_pipelines.md](README_pipelines.md) - パイプライン管理ツール
- [README_accounts.md](README_accounts.md) - アカウント管理ツール
- [aws_cache_clear_guide.md](aws_cache_clear_guide.md) - キャッシュ管理

### 🔍 機能詳細
- [query_filter_feature.md](query_filter_feature.md) - クエリフィルター
- [cache_analysis_improvement.md](cache_analysis_improvement.md) - キャッシュ分析

### 🛠️ 技術詳細
- [performance_optimization_summary.md](performance_optimization_summary.md) - パフォーマンス
- [pipeline_status_logic_update.md](pipeline_status_logic_update.md) - ステータス処理
- [statistics_fix_analysis.md](statistics_fix_analysis.md) - 統計処理
- [last_execution_fix_analysis.md](last_execution_fix_analysis.md) - 時刻処理

### 📋 設計資料
- [spec.md](spec.md) - システム仕様
- [cache_flow_diagram.md](cache_flow_diagram.md) - アーキテクチャ
- [project_structure.md](project_structure.md) - プロジェクト構造

## 🚀 クイックスタート

### 基本的な使用方法
```bash
# パイプライン一覧を表示
./get_pipelines.sh

# アカウント一覧を表示  
./get_accounts.sh

# キャッシュ分析
./get_pipelines.sh --analyze-cache
```

### 高度な使用方法
```bash
# 特定パイプラインのフィルタリング
./get_pipelines.sh --query 'pipelines[?ends_with(name, `customizations-pipeline`)]'

# JSON形式での出力
./get_pipelines.sh -f json

# 失敗したパイプラインのみ表示
./get_pipelines.sh -s Failed
```

## 📞 サポート

各ドキュメントには詳細な使用例とトラブルシューティング情報が含まれています。
問題が発生した場合は、該当する機能のドキュメントを参照してください。

---

---

**プロジェクト**: AFT Operations Toolkit (aft-ops-toolkit)  
**最終更新**: 2025年10月7日  
**バージョン**: 2.0.0