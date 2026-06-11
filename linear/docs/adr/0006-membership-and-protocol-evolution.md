# ADR 0006: メンバーシップ (招待/除外) と sync protocol の進化

## ステータス

Accepted（2026-06-11）

## コンテキスト

MVP (Phase 1-5) は 1 user = 1 workspace で、協調デモは「同一ユーザの 2 デバイス」だった。E1 として複数ユーザの membership (招待 / 除外 / role) を追加する。本 ADR の主題は機能そのものより、**動いている sync protocol に新しい entity を追加するとき何を決めるべきか**:

- workspace_member が op の対象になる (entity type の追加 = protocol の変更)
- 「email から userId を server が解決する」コマンドは、client が結果を予測できない
- member 除外は認可の喪失であり、確定 op の配信 (WS) 自体と矛盾する (除外された本人に push し続けるのか)
- bootstrap の `users` は members 由来 — member が消えたとき reducer 側の users と食い違うと parity が壊れる

## 決定

**登録済みユーザの email 直接指定で member に追加し、workspace_member を sync protocol の第 7 entity として lockstep 拡張する。**

- **招待 = `inviteMember { email, role }` (admin 限定)**。招待 token / メール送信はローカル完結方針によりスコープ外。未登録 email は 422、既 member は 409
- **protocol 進化は lockstep (同時デプロイ) 前提**: shared の `EntityTypeSchema` と Prisma enum を直接拡張する。monorepo で FE/BE が同一 commit から build されるため version negotiation を持たない。本番で rolling deploy するなら「未知 entityType を無視する寛容な reducer + protocol version」が必要になる — この差自体を記録として残す
- **server-resolved コマンドは楽観適用しない**: `applyCommand(inviteMember)` は no-op (`tempIdCount = 0`)。対象 userId を client が知り得ないため、確定 op (user 表示情報を payload に同梱) で反映する。「楽観できるコマンド / できないコマンド」の二分類が engine に入った
- **users は membership に従属**: member delete の reducer は members と users の両方から落とす。bootstrap の users が members 由来である以上、これが parity (ADR 0004) を保つ唯一の単純解。除外されたユーザを参照する assigneeId 等は fallback 表示 (`user#id`) に落ちる
- **除外 = 認可喪失 + WS kick**: REST は `assertMember` が以後 403 にするが、接続済み WS は生きているため、mutation の COMMIT + broadcast 後に `RealtimeService.kick` で 4403 close する。client (WsClient) は 4403 を「再接続しない close」として扱う

## 検討した選択肢

### 1. 登録済み email 直接追加 + lockstep 進化 ← 採用

- 学習対象 (protocol 進化 / server-resolved コマンド / 認可喪失の伝播) に直行し、メール往復などの周辺実装を持たない

### 2. 招待 token フロー (リンク発行 → 受諾)

- 実プロダクトの UX に近い
- 欠点: token 発行・期限・受諾画面という「よくある CRUD」が増えるだけで、sync engine の理解は深まらない。スコープ判定基準により除外

### 3. inviteMember を楽観適用する (email → 仮 member を表示)

- UI の即時性は上がる
- 欠点: userId・表示名を client が知らないため、仮 entity が「email だけの幽霊 member」になる。確定時の置換も id 対応が取れない (一時 id は **自分が採番する** insert にしか使えない)。却下して「楽観できないコマンド」の存在を仕様にした

### 4. 除外時に kick しない (自然消滅に任せる)

- 実装最小。REST は 403 になるので実害は限定的
- 欠点: 除外済みユーザに op を push し続けるのは認可境界の穴 (内容が漏れる)。即時 close が正しい

## 採用理由

- **学習価値**: 「protocol に entity を足す」一周 (shared スキーマ → Prisma enum migration → reducer → bootstrap → parity → client → UI) を、後方互換の論点 (lockstep vs version negotiation) 込みで踏める
- **アーキテクチャ妥当性**: server-resolved コマンドの非楽観化・認可喪失時の push 遮断は、実物の sync engine (Linear / Figma) が必ず持つ仕様
- **責務分離**: 認可は workspaces (assertAdmin) に、kick は mutations → realtime の既存一方向に乗る。ドメイン module は不変
- **将来の拡張性**: role 変更 (`updateMemberRole`) や「最後の admin を守る」制約は同じ枠に足せる

## 却下理由

- 案 2: 学びが薄い周辺実装が主になる
- 案 3: 一時 id の前提 (自己採番 insert) を壊す。幽霊 entity の置換問題を抱え込む
- 案 4: 認可境界の穴

## 引き受けるトレードオフ

- **除外ユーザの表示名が落ちる**: users を membership に従属させたため、過去の作成者/担当者の名前が `user#id` になる。発行済み op の payload (createdById 等) は不変なので整合は壊れない。気になるなら「users を独立 entity として op 配信する」派生 ADR で解ける
- **lockstep 前提**: rolling deploy 環境では protocol version が必要 (本リポでは負債として明記のみ)
- **自分自身の remove 禁止は最小ガード**: 「最後の admin を守る」一般則は未実装 (admin が 2 人いて互いに remove はできてしまう)

## このADRを守るテスト / 実装ポインタ

- `linear/backend/test/membership.e2e-spec.ts` — 招待/除外の認可 (403/409/422)・アクセス喪失
- `linear/backend/test/realtime.e2e-spec.ts` — removeMember で本人 socket 4403 close + 他メンバーへ delete op 配信
- `linear/backend/test/reducer-parity.e2e-spec.ts` — invite + remove を含む畳み込み ≡ bootstrap (users 従属の検証)
- `linear/shared/src/reducer.ts` — `removeMemberFromSnapshot` / inviteMember no-op
- `linear/client/src/sync-engine.test.ts` — server-resolved コマンドの非楽観 → 確定反映

## 関連 ADR

- ADR 0002: op log (本 ADR は entity を 1 つ追加)
- ADR 0003: 楽観適用 (「楽観できないコマンド」の例外を追加)
- ADR 0004: parity (users 従属はこれを保つための決定)
- ADR 0005: WS 配信 (kick = 認可喪失の伝播を追加)
