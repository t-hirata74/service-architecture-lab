class CreateRepositoryCollaborators < ActiveRecord::Migration[8.0]
  def change
    create_table :repository_collaborators do |t|
      t.references :repository, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 1

      t.timestamps
    end

    add_index :repository_collaborators, %i[repository_id user_id], unique: true
  end
end
