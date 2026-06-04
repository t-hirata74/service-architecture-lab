require "rails_helper"

# ADR 0001/0003/0004: DocumentChannel の購読認可 + op fan-out + viewer 拒否 + ephemeral cursor。
RSpec.describe DocumentChannel, type: :channel do
  let(:owner)  { create(:user) }
  let(:editor) { create(:user) }
  let(:viewer) { create(:user) }
  let(:document) { create(:document, owner:) }

  before do
    create(:document_member, document:, user: owner, role: "owner")
    create(:document_member, document:, user: editor, role: "editor")
    create(:document_member, document:, user: viewer, role: "viewer")
  end

  it "member は subscribe でき document stream に乗る" do
    stub_connection current_user: editor
    subscribe(document_id: document.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(document)
  end

  it "非 member は reject" do
    stub_connection current_user: create(:user)
    subscribe(document_id: document.id)
    expect(subscription).to be_rejected
  end

  it "editor の apply_operation は materialize + broadcast (seq 付き)" do
    stub_connection current_user: editor
    subscribe(document_id: document.id)

    expect do
      perform :apply_operation,
              "shape_id" => "A", "op_type" => "create",
              "payload" => { "kind" => "rect", "x" => 1 }, "lamport" => 1
    end.to have_broadcasted_to(document).from_channel(DocumentChannel).with { |data|
      d = data.deep_symbolize_keys
      expect(d[:type]).to eq("operation")
      expect(d[:op][:shape_id]).to eq("A")
      expect(d[:op][:seq]).to eq(1)
    }

    expect(document.canvas_objects.find_by(shape_id: "A").props["x"]).to eq(1)
  end

  it "viewer の apply_operation は拒否され materialize しない" do
    stub_connection current_user: viewer
    subscribe(document_id: document.id)

    expect do
      perform :apply_operation,
              "shape_id" => "A", "op_type" => "create",
              "payload" => { "kind" => "rect" }, "lamport" => 1
    end.not_to change(Operation, :count)
  end

  it "cursor は broadcast するが DB に書かない (ephemeral)" do
    stub_connection current_user: editor
    subscribe(document_id: document.id)

    expect do
      perform :cursor, "x" => 10, "y" => 20
    end.to have_broadcasted_to(document).from_channel(DocumentChannel).with { |data|
      expect(data.deep_symbolize_keys[:type]).to eq("cursor")
    }
    expect(Operation.count).to eq(0)
    expect(CanvasObject.count).to eq(0)
  end
end
