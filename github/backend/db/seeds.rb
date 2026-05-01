# Idempotent シード — Phase 5c の Playwright E2E 前提データ
# `bundle exec rails db:seed` で何度流しても結果が変わらないよう find_or_create_by! を使う

org = Organization.find_or_create_by!(login: "acme") { |o| o.name = "ACME" }

users = {
  alice: User.find_or_create_by!(login: "alice")   { |u| u.email = "alice@example.test";   u.name = "Alice" },
  bob:   User.find_or_create_by!(login: "bob")     { |u| u.email = "bob@example.test";     u.name = "Bob" },
  carol: User.find_or_create_by!(login: "carol")   { |u| u.email = "carol@example.test";   u.name = "Carol" }
}

# alice: org admin / bob: org member / carol: outside collaborator
Membership.find_or_create_by!(organization: org, user: users[:alice]) { |m| m.role = :admin }
Membership.find_or_create_by!(organization: org, user: users[:bob])   { |m| m.role = :member }
Membership.find_or_create_by!(organization: org, user: users[:carol]) { |m| m.role = :outside_collaborator }

repo = org.repositories.find_or_create_by!(name: "tools") do |r|
  r.description = "Internal tools (E2E seed)"
  r.visibility  = :private_visibility
end

# bob は repo に対して個別 maintain
RepositoryCollaborator.find_or_create_by!(repository: repo, user: users[:bob]) { |c| c.role = :maintain }

# Issue を 1 件 (PR と番号空間を共有することを E2E で確認するため)
Issue.find_or_create_by!(repository: repo, number: 1) do |i|
  i.author = users[:alice]
  i.title  = "First issue (seed)"
  i.body   = "Phase 5c E2E seed."
  i.state  = :open
end

# 番号カウンタをここまで進める
counter = RepositoryIssueNumber.find_or_create_by!(repository_id: repo.id)
counter.update!(last_number: [counter.last_number, 1].max)

# PR を 1 件 (head_sha = "seedsha" で固定 → ai-worker /check/run も同じ sha を打てる)
pr_number = if repo.pull_requests.exists?(head_sha: "seedsha000000000000000000000000000000000")
              repo.pull_requests.find_by(head_sha: "seedsha000000000000000000000000000000000").number
            else
              IssueNumberAllocator.next_for(repo)
            end

PullRequest.find_or_create_by!(repository: repo, number: pr_number) do |p|
  p.author          = users[:alice]
  p.title           = "Seed PR for E2E"
  p.body            = "Phase 5c seed."
  p.state           = :open
  p.mergeable_state = :mergeable
  p.head_ref        = "feature/seed"
  p.base_ref        = "main"
  p.head_sha        = "seedsha000000000000000000000000000000000"
end

puts "seed ok: org=#{org.login}, repo=#{repo.name}, issues=#{repo.issues.count}, prs=#{repo.pull_requests.count}"
