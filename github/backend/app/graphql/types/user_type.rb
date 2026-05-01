module Types
  class UserType < Types::BaseObject
    description "GitHub-style user account"

    field :id, ID, null: false
    field :login, String, null: false
    field :name, String, null: false
    field :email, String, null: true,
                  description: "Returned only when the viewer matches the user (field-level auth, ADR 0001)."

    def email
      object.id == context[:current_user]&.id ? object.email : nil
    end
  end
end
