# ADR 0003: Issue / PullRequest が共有する番号空間を行 lock で発番する。
# 並行採番でも重複しないことを spec で保証する。
class IssueNumberAllocator
  def self.next_for(repository)
    new(repository).allocate
  end

  def initialize(repository)
    @repository = repository
  end

  # @return [Integer] このリポジトリで未使用の次番号
  def allocate
    counter = RepositoryIssueNumber.find_or_create_by!(repository_id: @repository.id)
    counter.with_lock do
      counter.update!(last_number: counter.last_number + 1)
      counter.last_number
    end
  end
end
