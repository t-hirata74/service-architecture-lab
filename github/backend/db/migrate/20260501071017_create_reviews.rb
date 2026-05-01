class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.integer :state, null: false, default: 0
      t.text :body, null: false

      t.timestamps
    end

    add_index :reviews, %i[pull_request_id reviewer_id created_at]
  end
end
