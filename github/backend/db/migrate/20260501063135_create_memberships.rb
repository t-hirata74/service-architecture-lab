class CreateMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0

      t.timestamps
    end

    add_index :memberships, %i[organization_id user_id], unique: true
  end
end
