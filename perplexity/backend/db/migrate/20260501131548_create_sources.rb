class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :title, null: false, limit: 500
      t.string :url, limit: 1000
      t.text :body, null: false, size: :long
      t.timestamps
    end
  end
end
