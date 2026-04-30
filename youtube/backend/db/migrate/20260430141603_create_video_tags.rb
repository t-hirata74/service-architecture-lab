class CreateVideoTags < ActiveRecord::Migration[8.0]
  def change
    create_table :video_tags do |t|
      t.references :video, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :video_tags, [:video_id, :tag_id], unique: true
  end
end
