require 'rails_helper'

RSpec.describe PermissionResolver do
  let(:organization) { create(:organization) }
  let(:repository)   { create(:repository, organization:, visibility: :private_visibility) }
  let(:user)         { create(:user) }

  subject(:effective_role) { described_class.new(user, repository).effective_role }

  context "when user has no relation to the org" do
    it "returns :none on a private repo" do
      expect(effective_role).to eq(:none)
    end

    it "returns :read on a public repo" do
      repository.update!(visibility: :public_visibility)
      expect(effective_role).to eq(:read)
    end
  end

  context "when user is an org member" do
    before { Membership.create!(organization:, user:, role: :member) }

    it "inherits :read from org base role" do
      expect(effective_role).to eq(:read)
    end
  end

  context "when user is an org admin" do
    before { Membership.create!(organization:, user:, role: :admin) }

    it "inherits :admin" do
      expect(effective_role).to eq(:admin)
    end
  end

  context "when user is an outside_collaborator with explicit collaborator role" do
    before do
      Membership.create!(organization:, user:, role: :outside_collaborator)
      RepositoryCollaborator.create!(repository:, user:, role: :triage)
    end

    it "uses the collaborator role (outside has no base inheritance)" do
      expect(effective_role).to eq(:triage)
    end
  end

  context "when user is granted via team and personal collaborator" do
    let(:team) { create(:team, organization:) }

    before do
      Membership.create!(organization:, user:, role: :member)
      TeamMember.create!(team:, user:, role: :member)
      TeamRepositoryRole.create!(team:, repository:, role: :write)
      RepositoryCollaborator.create!(repository:, user:, role: :triage)
    end

    it "takes the maximum across (org base / team / collaborator)" do
      # base=read, team=write, collab=triage -> write
      expect(effective_role).to eq(:write)
    end
  end

  context "when user has admin via team" do
    let(:team) { create(:team, organization:) }

    before do
      Membership.create!(organization:, user:, role: :member)
      TeamMember.create!(team:, user:, role: :member)
      TeamRepositoryRole.create!(team:, repository:, role: :admin)
    end

    it "is allowed to merge" do
      resolver = described_class.new(user, repository)
      expect(resolver.can?(:merge)).to be(true)
      expect(resolver.can?(:admin_repo)).to be(true)
    end
  end

  context "when nil user (unauthenticated)" do
    let(:user) { nil }

    it "is :none on private" do
      expect(effective_role).to eq(:none)
    end

    it "is :read on public" do
      repository.update!(visibility: :public_visibility)
      expect(effective_role).to eq(:read)
    end
  end
end
