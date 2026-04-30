class Video < ApplicationRecord
  # ADR 0001: アップロード状態機械
  enum :status, {
    uploaded: 0,
    transcoding: 1,
    ready: 2,
    published: 3,
    failed: 4
  }

  belongs_to :user
  has_many :video_tags, dependent: :destroy
  has_many :tags, through: :video_tags

  # ADR 0002: ストレージは Active Storage local。本番想定は S3 + CloudFront を Terraform で示す
  has_one_attached :original
  has_one_attached :thumbnail

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 5_000 }
  validates :duration_seconds, numericality: { greater_than_or_equal_to: 0 },
                               allow_nil: true

  # 一覧で見せてよいのは published のみ
  scope :listable, -> { where(status: statuses[:published]).order(published_at: :desc) }
  # 詳細ページに到達してよい状態（公開直前の ready も内部確認向けに許容）
  scope :viewable, -> { where(status: [statuses[:ready], statuses[:published]]) }

  class InvalidTransition < StandardError; end

  # uploaded -> transcoding。ジョブ enqueue は after_commit で原子的に行われる
  # (ADR 0001: enqueue_after_transaction_commit = :always)
  def start_transcoding!
    transaction do
      raise InvalidTransition, "expected uploaded, got #{status}" unless uploaded?
      update!(status: :transcoding)
      TranscodeJob.perform_later(id)
    end
  end

  # transcoding -> ready
  def mark_ready!
    transaction do
      raise InvalidTransition, "expected transcoding, got #{status}" unless transcoding?
      update!(status: :ready)
    end
  end

  # transcoding/uploaded -> failed
  def mark_failed!(reason = nil)
    transaction do
      unless transcoding? || uploaded?
        raise InvalidTransition, "cannot fail from #{status}"
      end
      update!(status: :failed)
    end
    Rails.logger.warn("Video##{id} failed: #{reason}") if reason
  end

  # failed -> transcoding (リトライ)
  def retry_transcoding!
    transaction do
      raise InvalidTransition, "expected failed, got #{status}" unless failed?
      update!(status: :transcoding)
      TranscodeJob.perform_later(id)
    end
  end

  # ready -> published
  def publish!(now: Time.current)
    transaction do
      raise InvalidTransition, "expected ready, got #{status}" unless ready?
      update!(status: :published, published_at: now)
    end
  end
end
