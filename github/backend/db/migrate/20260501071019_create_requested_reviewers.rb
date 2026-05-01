class CreateRequestedReviewers < ActiveRecord::Migration[8.0]
  def change
    create_table :requested_reviewers do |t|
      t.references :pull_request, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :requested_reviewers, %i[pull_request_id user_id], unique: true
  end
end
