# committee-rails: request spec で OpenAPI 契約を検証する。
# 実 application middleware には差し込まない (test 専用)。
# 詳細: docs/api-style.md
Rails.application.config.committee = {
  schema_path: Rails.root.join("docs", "openapi.yml").to_s,
  query_hash_check: true,
  # multipart は OpenAPI に書ききれないので validate_request は無効化、response のみ
  parse_response_by_content_type: false
}
