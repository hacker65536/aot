

# 目的

AFT (AWS Control Tower Account Factory for Terraform) での `terraform plan`の実行

# 経緯
AFT (AWS Control Tower Account Factory for Terraform) の codepipeline 環境では plan 機能が提供されていなく、一般的に `terraform apply` の前に実行計画を確認いしたいため、AFTにおいて簡単に `terraform plan` ができるようにしたい

# 利用する技術スタック

bash 4系以上
jq
jinja


# 機能
cache 機能