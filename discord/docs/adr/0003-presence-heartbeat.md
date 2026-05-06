# ADR 0003: プレゼンスのハートビート設計

## ステータス

Accepted（2026-05-04）

## コンテキスト

Discord の **プレゼンス (online / offline / idle)** は WebSocket 接続の生死で決まる。WS 接続が `close` するイベントは TCP 切断で得られるが、以下のケースでは **TCP 視点では生きているが実質死んでいる** 状態が起きる:

- ノート PC のサスペンド (TCP がそのまま固まる)
- ロードバランサ / プロキシが idle connection を裏で殺す
- スマホがネットワーク切替 (Wi-Fi → 4G) で前接続を放置

実 Discord は **Gateway protocol** で以下のハートビート規約を採用:

1. `op 10 HELLO`: server → client、`heartbeat_interval` (例 41250ms) を送る
2. `op 1 HEARTBEAT`: client → server、interval ごとに送る (`d` フィールドに最後の seq)
3. `op 11 HEARTBEAT_ACK`: server → client
4. server 側は **`heartbeat_interval × 1.5` 内に HEARTBEAT が来なかったら** 接続を死んでいると判定して close + offline broadcast

WebSocket protocol 自身にも **ping/pong control frame** (RFC 6455) があるが:

- gorilla/websocket では `SetPingHandler` / `SetPongHandler` で受けるが、**broadcast 経路と切り離されている** (control frame は読み専用)
- ブラウザの WebSocket API は **`ping/pong frame を JS から送れない**。受信時の event も拾えない (browser が自動で pong を返すだけ)

なので **app 層 HEARTBEAT** が必要。

制約:

- ローカル開発で挙動を体感したいので `heartbeat_interval` は短め (例: 10000 ms)、production は長め (40000 ms)
- 学習対象は **「app 層 heartbeat の状態管理を Go の goroutine + channel で書く」**
- プレゼンスは guild 単位で broadcast される (1 ユーザの状態変化は、その人と同じ guild のメンバ全員に届く)

## 決定

**「app 層 HEARTBEAT (op 1 / op 11) + Hub 内で per-client `lastHeartbeatAt` を ticker で監視 + 死亡判定で offline broadcast」** を採用する。

### Gateway op codes

```
op 0  DISPATCH         server → client  (event: MESSAGE_CREATE / PRESENCE_UPDATE)
op 1  HEARTBEAT        client → server  ({"op":1, "d": last_seq})
op 2  IDENTIFY         client → server  ({"op":2, "d": {"token": "...", "guild_id": 1}})
op 10 HELLO            server → client  ({"op":10, "d": {"heartbeat_interval": 10000}})
op 11 HEARTBEAT_ACK    server → client  ({"op":11})
```

### Server side flow

1. WS upgrade 成功 → server は HELLO を送信
2. client は IDENTIFY で `(token, guild_id)` を送信。server は token 検証 + guild membership 確認 → Hub に register
3. Hub goroutine は `time.NewTicker(heartbeat_interval / 2)` で監視ループ。各 tick で `now - client.lastHeartbeatAt > heartbeat_interval * 1.5` なら **死亡判定** → unregister + close(send)
4. client が HEARTBEAT を送ると、`Client.readPump` が `client.lastHeartbeatAt = time.Now()` を更新 (atomic) + HEARTBEAT_ACK を送り返す
5. unregister 経路で **PRESENCE_UPDATE (offline)** を broadcast

### `lastHeartbeatAt` の更新

- Client struct のフィールドとして `atomic.Int64 (UnixNano)` で保持
- readPump (Client goroutine) が更新、Hub の監視 ticker が読む → **lock 不要 / racy にならない**
- atomic で十分な理由: 「正確な値より、ある程度新しい値で `> threshold` を判定できれば良い」

### プレゼンス state machine

最小は **online / offline の 2 状態**。`idle` (5 分操作なし) 等は派生 ADR で追加余地として残す。

```
register → online    → broadcast PRESENCE_UPDATE(online)
unregister → offline → broadcast PRESENCE_UPDATE(offline)
```

state は `Hub.presences[user_id]` (Hub goroutine 専有) で持つ。1 user が同 guild に複数接続している場合 (multi-tab) は **接続数カウント**で状態を決める (count > 0 なら online)。

### READY フレームに presence snapshot を載せる (join 時の初期同期)

新しい client は WS 接続直後に、既に online な他メンバーを **即座に** 観測できる必要がある。後発の `PRESENCE_UPDATE` 配信を待つ実装だと「自分が join した後に状態変化が無いメンバー」は永久に online list に出ない。

そこで Hub の register handler は次の 2 つを **同一の goroutine ステップで** 実行する:

1. 既存 client へ `PRESENCE_UPDATE(online)` を fanout（既存通り）
2. 現在の `presence` map から **自分以外** をスナップショット化し、register リクエストに付随する response channel に送り返す

gateway は `RequestRegisterWithSnapshot()` を呼んで snapshot を受け取り、それを `READY.presences` に詰めて送信する。これにより以下の不変条件が成立する:

- **ある時点で online だったメンバーは、新規接続者の READY で必ず観測できる**
- snapshot の取得と client の clients map 追加は Hub goroutine 内で atomic（CSP / ADR 0002）
- 自分自身は snapshot から除外する（READY.user で別途渡しているため）

## 検討した選択肢

### 1. app 層 HEARTBEAT + Hub 監視 ticker ← 採用

- 利点: ブラウザから JS で送れる (普通の WS message)
- 利点: HEARTBEAT_ACK の往復で round-trip 死活が分かる
- 利点: Discord 公式 protocol と整合
- 欠点: client 側に「定期送信」のコードが必要 (frontend の lib に小さな loop が要る)

### 2. WebSocket ping/pong frame のみ

- 利点: protocol 標準、自前実装不要
- 欠点: **ブラウザの WebSocket API は ping を送れない**。サーバ側 `Conn.WriteControl(PingMessage, ...)` で送れるが、ブラウザは自動 pong を返すだけで JS event が出ないので「アプリが生きてる」ことの証明にならない (タブが固まっていてもブラウザ自体が応答する)
- 欠点: 学習対象 (heartbeat protocol design) を捨てる

### 3. TCP keepalive のみ

- 利点: ゼロコード
- 欠点: 中間プロキシ (ALB / nginx) が idle TCP を殺すと検知できない
- 欠点: app 層の不変条件 (ユーザ操作が無いタブのプレゼンス) を語れない

### 4. server が HELLO で interval を可変通知 (現実装)

- 採用済み: HELLO の `d.heartbeat_interval` を server 側 config で変えられる
- 派生として interval にジッタを加える (load smoothing) 余地

### 5. 死亡判定後に再接続猶予を与える

- 利点: 一時的 NW 断にも耐える (例: 30 秒以内に IDENTIFY/RESUME してきたら presence 維持)
- 欠点: 状態管理が複雑 (zombie tombstone が残る)
- **派生 ADR で扱う** (op `RESUME` 実装と一緒に)

### 6. Redis に presence を集約

- 利点: multi-process gateway で必要
- 欠点: 単一プロセス前提 (ADR 0001) では不要
- **shard 化派生 ADR で扱う**

## 採用理由

- **学習価値**: Go の `time.Ticker` + select + atomic を実装で使える題材。「app 層 protocol を自前定義する」体験は WS gateway の核
- **アーキテクチャ妥当性**: 実 Discord と同形 protocol (op 1 / 10 / 11)。再現性が高い
- **責務分離**: heartbeat の更新は Client goroutine、監視は Hub goroutine で **専有 owner が分かれる**
- **テスタビリティ**: `heartbeat_interval` を test で 100ms 等に短くすれば、死亡判定までを 1 秒以内で再現できる

## 却下理由

- **WS ping/pong のみ**: ブラウザから ping 送れない、タブ固まり検知できない
- **TCP keepalive**: 中間プロキシで殺される、app 層の生死語れない
- **Redis 集約**: 単一プロセス前提では過剰、shard 派生で再検討

## 引き受けるトレードオフ

- **client 側 frontend の HEARTBEAT 送信コード必須**: lib に 5-10 行の `setInterval` を仕込む。失敗したら接続死亡 → 自動再接続戦略を frontend lib に書く
- **multi-tab の同時接続**: 1 user が 2 タブで同じ guild に居る場合、片方のタブを閉じても presence は online のまま (count > 0)。両方閉じて初めて offline broadcast
- **クロックスキュー**: server 内の time.Now() で判定するので OK。client clock は信用しない
- **HEARTBEAT が遅延した場合の偽陰性**: GC pause / network jitter で 1 回飛ぶこともある。`× 1.5` 余裕で吸収
- **HEARTBEAT 多発による負荷**: 1 client = 10000ms 周期 → 1000 client で 100 msg/s。Hub goroutine の readPump で吸収するので Hub broadcast には影響しない
- **idle / dnd / invisible の不在**: 派生 ADR でやる。MVP は online / offline のみ
- **再接続時の presence flicker**: ws 切れる → offline broadcast → 即再接続 → online broadcast、と短時間で 2 件流れる。frontend は debounce で吸収する余地

## このADRを守るテスト / 実装ポインタ（Phase 3 で実装）

- `discord/backend/internal/gateway/protocol.go` — op codes 定数 + `Hello` / `Heartbeat` / `Identify` 等の struct
- `discord/backend/internal/gateway/client.go` — `lastHeartbeatAt atomic.Int64` + readPump で更新
- `discord/backend/internal/gateway/hub.go` — `time.Ticker` で監視 + 死亡判定 → unregister
- `discord/backend/internal/gateway/hub_test.go`:
  - `heartbeat_interval=100ms` で起動、HEARTBEAT 送らずに 200ms 待つと unregister される
  - HEARTBEAT を流し続ける限り unregister されない
  - unregister 経路で PRESENCE_UPDATE が broadcast される

## 関連 ADR

- ADR 0001: 単一プロセス per-guild Hub (presence は Hub 内で管理)
- ADR 0002: Hub の goroutine + channel pattern (監視 ticker は Hub goroutine の select に統合)
- ADR 0010 (派生予定): op `RESUME` / 再接続猶予期間 / zombie tombstone
- ADR 0011 (派生予定): idle / dnd / invisible の追加
