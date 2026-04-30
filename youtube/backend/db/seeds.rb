# Phase 2: 動画一覧 / 詳細 UI を確認するためのデモデータ。
# 冪等になるよう find_or_create_by! を使う。

users = [
  { email: "alice@example.com", name: "Alice" },
  { email: "bob@example.com",   name: "Bob" },
  { email: "carol@example.com", name: "Carol" }
].map { |attrs| User.find_or_create_by!(email: attrs[:email]) { |u| u.name = attrs[:name] } }

tag_names = %w[rails ruby python ml ai database tutorial introduction]
tags = tag_names.map { |n| Tag.find_or_create_by!(name: n) }
tag_by = tags.index_by(&:name)

now = Time.current
samples = [
  { title: "Rails 8 + Solid Queue 入門", description: "Redis を使わずにバックグラウンドジョブを動かす方法を 10 分で。",
    user: users[0], status: :published, duration_seconds: 612, published_at: now - 2.days,
    tag_names: %w[rails ruby tutorial introduction] },
  { title: "Python で簡易レコメンダ実装",  description: "Jaccard 類似度で関連動画ランキングを作る。実 ML なし。",
    user: users[1], status: :published, duration_seconds: 904, published_at: now - 1.day,
    tag_names: %w[python ml ai tutorial] },
  { title: "MySQL ngram 全文検索",         description: "日本語タイトル検索を最小コストで動かす設定とトレードオフ。",
    user: users[2], status: :published, duration_seconds: 487, published_at: now - 5.hours,
    tag_names: %w[database tutorial] },
  { title: "Active Storage で動画を扱う",  description: "ローカルディスク → S3 への移行を意識したアタッチメント設計。",
    user: users[0], status: :published, duration_seconds: 730, published_at: now - 30.minutes,
    tag_names: %w[rails database] },
  { title: "状態機械で考えるアップロード", description: "uploaded → transcoding → ready → published を一貫して管理する。",
    user: users[1], status: :ready, duration_seconds: 555, published_at: nil,
    tag_names: %w[rails introduction] },
  { title: "[非公開] エンコード途中サンプル", description: "transcoding 状態の動画は一覧に出ないことを確認するためのデータ。",
    user: users[2], status: :transcoding, duration_seconds: nil, published_at: nil,
    tag_names: %w[rails] }
]

samples.each do |attrs|
  video = Video.find_or_initialize_by(title: attrs[:title])
  video.assign_attributes(
    description: attrs[:description],
    user: attrs[:user],
    status: attrs[:status],
    duration_seconds: attrs[:duration_seconds],
    published_at: attrs[:published_at]
  )
  video.save!
  video.tags = attrs[:tag_names].map { |n| tag_by[n] }
end

puts "Seeded: users=#{User.count} videos=#{Video.count} tags=#{Tag.count}"
