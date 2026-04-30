class CreateChannels < ActiveRecord::Migration[8.0]
  def change
    create_table :channels do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.text :topic
      t.timestamps precision: 6

      t.index [:kind, :name], unique: true
    end
  end
end
