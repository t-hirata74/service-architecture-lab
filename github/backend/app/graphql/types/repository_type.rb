module Types
  class RepositoryType < Types::BaseObject
    description "GitHub-style repository (ADR 0002 / 0003)."

    field :id, ID, null: false
    field :name, String, null: false
    field :description, String, null: true
    field :visibility, Types::RepositoryVisibilityEnum, null: false
    field :owner, Types::OrganizationType, null: false
    field :viewer_permission, Types::RepositoryPermissionEnum, null: false,
          description: "Effective role of the current viewer (ADR 0002)."

    field :issues, [Types::IssueType], null: false do
      argument :state, Types::IssueStateEnum, required: false
      argument :first, Integer, required: false, default_value: 30
    end

    field :pull_requests, [Types::PullRequestType], null: false do
      argument :state, Types::PullRequestStateEnum, required: false
      argument :first, Integer, required: false, default_value: 30
    end

    field :labels, [Types::LabelType], null: false

    def owner
      object.organization
    end

    # ADR 0001: 一覧で N 件 repository を返すケースの N+1 を Dataloader で潰す。
    def viewer_permission
      dataloader.with(Sources::ViewerPermissionSource, context[:current_user]).load(object)
    end

    def issues(state: nil, first: 30)
      scope = object.issues.order(number: :desc)
      scope = scope.where(state: state) if state
      scope.limit(first)
    end

    def pull_requests(state: nil, first: 30)
      scope = object.pull_requests.order(number: :desc)
      scope = scope.where(state: state) if state
      scope.limit(first)
    end

    def labels
      object.labels.order(:name)
    end
  end
end
