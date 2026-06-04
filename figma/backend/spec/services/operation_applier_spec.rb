require "rails_helper"

# figma の中核不変条件を固定する spec (ADR 0001 / 0002)。
# 目玉は #convergence: 同一 op 集合を任意の順で適用しても全 actor が同一の
# materialized 状態に収束する (= LWW-CRDT の収束性)。shopify の 100-thread 在庫
# spec / discord の race spec に相当する「このサービス固有の整合性を縛るテスト」。
RSpec.describe OperationApplier do
  let(:alice) { create(:user, name: "alice") }
  let(:bob)   { create(:user, name: "bob") }

  def apply(document, actor:, shape_id:, op_type:, payload:, lamport:)
    described_class.call(document:, actor:, shape_id:, op_type:, payload:, lamport:)
  end

  # 比較可能な canvas 状態。seq / last_seq / timestamps は適用順で正当に変わるので除外し、
  # 収束対象 (kind / props / prop_clocks / deleted) のみを取り出す。
  def canvas_state(document)
    document.canvas_objects.reload.map do |o|
      { shape_id: o.shape_id, kind: o.kind, props: o.props,
        prop_clocks: o.prop_clocks, deleted: o.deleted }
    end.sort_by { |h| h[:shape_id] }
  end

  describe "基本適用" do
    it "create → update を materialize し、op log に seq を昇順採番する" do
      doc = create(:document, owner: alice)

      apply(doc, actor: alice, shape_id: "A", op_type: "create",
                 payload: { kind: "rect", x: 0, y: 0 }, lamport: 1)
      apply(doc, actor: alice, shape_id: "A", op_type: "update",
                 payload: { x: 10 }, lamport: 2)

      obj = doc.canvas_objects.find_by(shape_id: "A")
      expect(obj.kind).to eq("rect")
      expect(obj.props).to eq("x" => 10, "y" => 0)
      expect(doc.reload.version).to eq(2)
      expect(doc.operations.order(:seq).pluck(:seq)).to eq([ 1, 2 ])
    end

    it "viewer 用 role 判定はサービス外 (controller/channel) だが、create は kind を要求する" do
      doc = create(:document, owner: alice)
      expect do
        apply(doc, actor: alice, shape_id: "A", op_type: "create", payload: { x: 0 }, lamport: 1)
      end.to raise_error(OperationApplier::InvalidOperation, /kind/)
    end
  end

  describe "LWW (last-writer-wins) per property" do
    it "同一プロパティは高い lamport が勝つ (適用順に依存しない)" do
      [ %i[low high], %i[high low] ].each do |order|
        doc = create(:document, owner: alice)
        apply(doc, actor: alice, shape_id: "A", op_type: "create",
                   payload: { kind: "rect", x: 0 }, lamport: 1)
        ops = {
          low: -> { apply(doc, actor: alice, shape_id: "A", op_type: "update", payload: { x: 10 }, lamport: 2) },
          high: -> { apply(doc, actor: bob, shape_id: "A", op_type: "update", payload: { x: 20 }, lamport: 3) }
        }
        order.each { |k| ops[k].call }

        expect(doc.canvas_objects.find_by(shape_id: "A").props["x"]).to eq(20)
      end
    end

    it "lamport が同値のときは actor_id が大きい方が勝つ (決定的 tie-break)" do
      low_actor, high_actor = [ alice, bob ].sort_by(&:id)

      [ [ low_actor, high_actor ], [ high_actor, low_actor ] ].each do |first, second|
        doc = create(:document, owner: alice)
        apply(doc, actor: alice, shape_id: "A", op_type: "create", payload: { kind: "rect" }, lamport: 1)
        apply(doc, actor: first,  shape_id: "A", op_type: "update", payload: { x: 1 }, lamport: 5)
        apply(doc, actor: second, shape_id: "A", op_type: "update", payload: { x: 2 }, lamport: 5)

        obj = doc.canvas_objects.find_by(shape_id: "A")
        # 高い actor_id の値が勝つ。high_actor が x をいくつにしたかで決まる。
        expected = (high_actor == first ? 1 : 2)
        expect(obj.props["x"]).to eq(expected)
        expect(obj.prop_clocks["x"]).to eq("l" => 5, "a" => high_actor.id)
      end
    end

    it "delete は 'deleted' プロパティへの LWW op として扱う (update と競合解決できる)" do
      doc = create(:document, owner: alice)
      apply(doc, actor: alice, shape_id: "A", op_type: "create", payload: { kind: "rect", x: 0 }, lamport: 1)
      # delete(lamport 2) より後に高い lamport の update(3) が来たら復活する (delete-wins ではない)。
      apply(doc, actor: alice, shape_id: "A", op_type: "delete", payload: {}, lamport: 2)
      apply(doc, actor: bob,   shape_id: "A", op_type: "update", payload: { deleted: false, x: 9 }, lamport: 3)

      obj = doc.canvas_objects.find_by(shape_id: "A")
      expect(obj.deleted).to be(false)
      expect(obj.props["x"]).to eq(9)
    end
  end

  describe "out-of-order create (update が create より先に届く)" do
    it "placeholder kind を経ても create の kind に収束する" do
      doc = create(:document, owner: bob)
      # B は ellipse。update を先に適用 → 仮 kind=rect で初期化される。
      apply(doc, actor: bob, shape_id: "B", op_type: "update", payload: { x: 200 }, lamport: 2)
      expect(doc.canvas_objects.find_by(shape_id: "B").kind).to eq("rect") # placeholder

      apply(doc, actor: bob, shape_id: "B", op_type: "create", payload: { kind: "ellipse", x: 100, y: 0 }, lamport: 1)

      obj = doc.canvas_objects.find_by(shape_id: "B")
      expect(obj.kind).to eq("ellipse")        # create が kind を正す
      expect(obj.props["x"]).to eq(200)        # x は高 lamport(2) が残る
      expect(obj.props["y"]).to eq(0)
    end
  end

  describe "append-only ログ" do
    it "operations 行は永続後 readonly で、seq は document 内で一意" do
      doc = create(:document, owner: alice)
      res = apply(doc, actor: alice, shape_id: "A", op_type: "create", payload: { kind: "rect" }, lamport: 1)

      persisted = Operation.find(res.operation.id)
      expect(persisted.readonly?).to be(true)
      expect { persisted.update!(lamport: 999) }.to raise_error(ActiveRecord::ReadOnlyRecord)

      expect do
        Operation.create!(document: doc, actor: alice, shape_id: "A", op_type: "update",
                          payload: {}, lamport: 2, seq: 1, created_at: Time.current)
      end.to raise_error(ActiveRecord::RecordInvalid) # seq=1 は既出
    end
  end

  describe "#convergence — 任意順で適用しても同一状態に収束する (LWW-CRDT 不変条件)" do
    # 各 op は (actor, shape, type, payload, lamport)。プロパティごとに勝者 (max lamport, tie は actor_id)
    # が一意に決まるよう設計しているので、適用順に依存せず最終状態は一意。
    def op_specs
      [
        { actor: alice, shape_id: "A", op_type: "create", payload: { kind: "rect", x: 0, y: 0, fill: "#fff" }, lamport: 1 },
        { actor: bob,   shape_id: "B", op_type: "create", payload: { kind: "ellipse", x: 100, y: 0 }, lamport: 1 },
        { actor: alice, shape_id: "A", op_type: "update", payload: { x: 10 }, lamport: 2 },
        { actor: bob,   shape_id: "A", op_type: "update", payload: { x: 20 }, lamport: 3 },  # x 勝者
        { actor: alice, shape_id: "A", op_type: "update", payload: { fill: "#f00" }, lamport: 4 }, # fill 勝者
        { actor: bob,   shape_id: "B", op_type: "update", payload: { x: 200 }, lamport: 2 },  # B.x 勝者
        { actor: alice, shape_id: "B", op_type: "delete", payload: {}, lamport: 3 }           # B.deleted 勝者
      ]
    end

    def apply_all(document, specs)
      specs.each { |s| apply(document, **s) }
    end

    let(:reference_state) do
      doc = create(:document, owner: alice)
      apply_all(doc, op_specs)
      canvas_state(doc)
    end

    it "reference (定義順) の最終状態が期待値どおり" do
      a = reference_state.find { |h| h[:shape_id] == "A" }
      b = reference_state.find { |h| h[:shape_id] == "B" }

      expect(a[:kind]).to eq("rect")
      expect(a[:props]).to eq("x" => 20, "y" => 0, "fill" => "#f00")
      expect(a[:deleted]).to be(false)

      expect(b[:kind]).to eq("ellipse")
      expect(b[:props]).to eq("x" => 200, "y" => 0, "deleted" => true)
      expect(b[:deleted]).to be(true)
    end

    it "逆順・複数のシャッフル順でも reference と同一状態に収束する" do
      orders = [
        op_specs.reverse,
        *Array.new(12) { |i| op_specs.shuffle(random: Random.new(1000 + i)) }
      ]

      orders.each_with_index do |specs, i|
        doc = create(:document, owner: alice)
        apply_all(doc, specs)
        expect(canvas_state(doc)).to eq(reference_state),
          "permutation ##{i} が reference と異なる状態に収束した"
      end
    end
  end
end
