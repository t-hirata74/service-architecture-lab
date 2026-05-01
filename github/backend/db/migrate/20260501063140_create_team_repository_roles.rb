class CreateTeamRepositoryRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :team_repository_roles do |t|
      t.references :team, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.integer :role, null: false, default: 1

      t.timestamps
    end

    add_index :team_repository_roles, %i[team_id repository_id], unique: true
  end
end
