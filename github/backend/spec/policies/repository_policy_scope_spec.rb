require 'rails_helper'

RSpec.describe RepositoryPolicy::Scope do
  let!(:org)             { create(:organization, login: "acme") }
  let!(:other_org)       { create(:organization, login: "other") }
  let!(:public_repo)     { create(:repository, organization: org, visibility: :public_visibility, name: "public") }
  let!(:private_repo)    { create(:repository, organization: org, visibility: :private_visibility, name: "private") }
  let!(:other_org_repo)  { create(:repository, organization: other_org, visibility: :private_visibility, name: "secret") }

  def resolve(user)
    described_class.new(user, Repository.all).resolve
  end

  it "returns only public repos when user is nil" do
    expect(resolve(nil)).to contain_exactly(public_repo)
  end

  it "returns all org repos for an org member" do
    user = create(:user)
    Membership.create!(organization: org, user: user, role: :member)
    expect(resolve(user)).to contain_exactly(public_repo, private_repo)
  end

  it "returns all org repos for an org admin" do
    user = create(:user)
    Membership.create!(organization: org, user: user, role: :admin)
    expect(resolve(user)).to contain_exactly(public_repo, private_repo)
  end

  it "outside_collaborator does NOT inherit org base — only sees public" do
    user = create(:user)
    Membership.create!(organization: org, user: user, role: :outside_collaborator)
    expect(resolve(user)).to contain_exactly(public_repo)
  end

  it "outside_collaborator with explicit collaborator grant sees that one private repo" do
    user = create(:user)
    Membership.create!(organization: org, user: user, role: :outside_collaborator)
    RepositoryCollaborator.create!(repository: private_repo, user: user, role: :read)
    expect(resolve(user)).to contain_exactly(public_repo, private_repo)
  end

  it "team grant in another org adds visibility to that org's repo" do
    user = create(:user)
    team = create(:team, organization: other_org)
    TeamMember.create!(team: team, user: user, role: :member)
    TeamRepositoryRole.create!(team: team, repository: other_org_repo, role: :read)
    expect(resolve(user)).to contain_exactly(public_repo, other_org_repo)
  end
end
