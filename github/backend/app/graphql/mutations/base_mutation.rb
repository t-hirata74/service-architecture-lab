module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    # Pundit policy 実行を mutation に薄く流す
    def authorize!(record, action)
      policy = Pundit.policy(context[:current_user], record)
      raise GraphQL::ExecutionError, "Forbidden" unless policy.public_send(action)
    end

    def current_user!
      user = context[:current_user]
      raise GraphQL::ExecutionError, "Unauthenticated" unless user
      user
    end
  end
end
