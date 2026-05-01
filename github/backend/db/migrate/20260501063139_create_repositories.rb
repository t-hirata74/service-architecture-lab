class CreateRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :repositories do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :visibility, null: false, default: 0

      t.timestamps
    end

    add_index :repositories, %i[organization_id name], unique: true
  end
end
