class CreateTeams < ActiveRecord::Migration[8.0]
  def change
    create_table :teams do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false, default: ""

      t.timestamps
    end

    add_index :teams, %i[organization_id slug], unique: true
  end
end
