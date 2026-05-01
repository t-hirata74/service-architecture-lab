# ADR 0003: Issue / PullRequest が共有する番号空間。
# 採番は IssueNumberAllocator が `with_lock` で行う。
class RepositoryIssueNumber < ApplicationRecord
  belongs_to :repository
end
