class Tag < ApplicationRecord
  has_many :video_tags, dependent: :destroy
  has_many :videos, through: :video_tags

  validates :name, presence: true, uniqueness: true, length: { maximum: 50 }

  def self.upsert_all_by_name(names)
    names = Array(names).map { |n| n.to_s.strip.downcase }.reject(&:empty?).uniq
    return [] if names.empty?
    now = Time.current
    rows = names.map { |n| { name: n, created_at: now, updated_at: now } }
    # MySQL は ON DUPLICATE KEY UPDATE で衝突解決するため :unique_by 不要 (PG とは挙動が異なる)
    upsert_all(rows)
    where(name: names)
  end
end
