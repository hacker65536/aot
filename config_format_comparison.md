# Bashスクリプト向け設定ファイル形式の比較

## 1. Bash変数形式 (.conf/.env)
**最もBashネイティブ**

```bash
# pipeline_config.conf
AWS_DEFAULT_PROFILE="default"
AWS_REGION="ap-northeast-1"
AWS_PIPELINES_PROFILE="pipeline-account"
AWS_ACCOUNTS_PROFILE="organizations-account"
CACHE_TTL=1800
DISPLAY_FORMAT="table"
DISPLAY_QUIET=false
PERFORMANCE_MAX_PARALLEL=15
```

**メリット:**
- Bashで直接`source`できる
- 最もシンプルで高速
- 環境変数として扱える
- パースが不要

**デメリット:**
- セクション分けができない
- コメントが制限的
- 複雑な構造には不向き

## 2. INI形式 (現在使用中)
**構造化された設定**

```ini
[aws]
default_profile = default
[aws.pipelines]
profile = pipeline-account
```

**メリット:**
- セクション分けが可能
- 読みやすい
- 多くのツールでサポート

**デメリット:**
- パース処理が複雑
- Bashネイティブではない

## 3. YAML形式
**最も表現力が高い**

```yaml
aws:
  default_profile: default
  pipelines:
    profile: pipeline-account
  accounts:
    profile: organizations-account
```

**メリット:**
- 階層構造が表現しやすい
- 配列やオブジェクトも扱える

**デメリット:**
- yqなど外部ツールが必要
- パース処理が重い

## 4. JSON形式
**プログラム処理向け**

```json
{
  "aws": {
    "pipelines": {"profile": "pipeline-account"}
  }
}
```

**メリット:**
- jqで処理可能
- 構造化データに適している

**デメリット:**
- コメントが書けない
- 人間が編集しにくい

## 推奨: Bash変数形式 (.conf)

Bashスクリプトには**Bash変数形式**が最適です。理由：

1. **ネイティブサポート**: `source`で直接読み込める
2. **高速**: パース処理が不要
3. **シンプル**: 追加の依存関係なし
4. **デバッグしやすい**: 変数の値が直接確認できる
5. **環境変数との親和性**: 既存の環境変数と統合しやすい