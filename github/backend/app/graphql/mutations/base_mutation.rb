module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    def current_user!
      user = context[:current_user]
      raise GraphQL::ExecutionError, "Unauthenticated" unless user
      user
    end

    # ADR 0002: 認可は **Pundit policy 経由**に統一する (PermissionResolver は policy の中で呼ぶ)。
    # `strict: true` (default) は GraphQL の execution error として上に伝える。
    # `strict: false` を指定すると bool を返し、呼び出し側が payload の errors として返せる。
    def authorize!(record, action, strict: true)
      allowed = Pundit.policy(context[:current_user], record).public_send(action)
      return true if allowed
      raise GraphQL::ExecutionError, "Forbidden" if strict
      false
    end
  end
end
