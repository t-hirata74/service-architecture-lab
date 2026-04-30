class CreateVideos < ActiveRecord::Migration[8.0]
  def change
    create_table :videos do |t|
      t.string :title, null: false
      t.text :description
      # status: 0=uploaded, 1=transcoding, 2=ready, 3=published, 4=failed (ADR 0001)
      t.integer :status, null: false, default: 0
      t.integer :duration_seconds
      t.datetime :published_at
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :videos, :status
    add_index :videos, :published_at

    # 全文検索 (ADR 0004): MySQL 8 ngram parser で日本語対応
    execute <<~SQL.squish
      ALTER TABLE videos
      ADD FULLTEXT INDEX index_videos_on_title_and_description (title, description)
      WITH PARSER ngram
    SQL
  end
end
