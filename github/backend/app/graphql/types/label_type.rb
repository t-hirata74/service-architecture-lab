module Types
  class LabelType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :color, String, null: false
  end
end
