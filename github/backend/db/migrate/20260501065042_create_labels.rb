class CreateLabels < ActiveRecord::Migration[8.0]
  def change
    create_table :labels do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "888888"

      t.timestamps
    end

    add_index :labels, %i[repository_id name], unique: true
  end
end
