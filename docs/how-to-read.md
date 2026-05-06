# このリポの読み方

このリポジトリは「設計判断と学習プロセスを残すこと」を一次目的にしている。コードは目的ではなく、**設計判断を裏付けるための実装証拠**として置いている。

ここでは、外部の閲覧者（採用担当・他のエンジニア・将来の自分）が短時間で要点を掴めるよう、リポの思想と読み方を 1 ページに集約する。

---

## 1. このリポは何か / 何ではないか

**このリポは:**

- 有名 SaaS のアーキテクチャを **「そのサービスが解いている技術課題」単位で抽出**し、ローカル完結のミニマム実装で再現したもの
- 9 サービス × 平均 4-6 本の ADR で、累計 **40 本の設計判断**を残してある
- 同じ技術課題（リアルタイム配信 / 認可 / 整合性 / streaming など）を **複数サービスで違う形で解き、対比できる**ように設計してある

**このリポは「ではない」もの:**

- プロダクトのクローン: 機能網羅は最初から除外している
- 本番運用想定: 認証・課金・スケール対策は MVP レベルでしか作らない
- ライブラリ・SDK のショウケース: 外部依存を最小化し、**自分でモデリングする**ことを優先する

---

## 2. なぜローカル完結 / 外部 SaaS 禁止か

LLM API・マネージド検索・決済 SaaS など、**外部に投げれば「解けたことになる」要素は意図的に禁止**している。

理由は単純で、このリポは **「自分で設計してみる」が学習目的**だから。SDK を貼って動かすのは設計学習にならない。代わりに

- LLM 応答 → ai-worker でルールベースのモック（tool call JSON も含めて自前で組み立てる）
- 決済・動画コーデック・通知 → ダミーデータ + 状態遷移だけ作る
- ベクタ検索 → MySQL に BLOB で埋め込みを置き numpy で cosine を取る (`perplexity/`)

「外部に頼らず代替実装した結果、何が削げ落ちたか / 何が見えたか」が ADR の主成分になる。

---

## 3. なぜ ADR を必須にしているか

各サービスに **最低 3 本の ADR** を要求している。理由:

- **判断の理由は時間が経つと消える** — コードからは「何をやったか」しか復元できない。「なぜそれを選び、何を捨てたか」は文書でしか残らない
- **対比のため** — 9 サービスで同じ課題（例: 認可 / streaming / 整合性）を別の形で解いている。**ADR を読むと "違う設計を試した経験" として通読できる**
- **ポートフォリオとしての耐久性** — 実装は陳腐化するが、「このトレードオフを踏んでこう選んだ」という思考は陳腐化しにくい

ADR の書式は [`docs/adr-template.md`](adr-template.md)。横断インデックスは [`docs/adr-index.md`](adr-index.md)。

---

## 4. 「完成の定義」は網羅ではなく「学びと動作確認」

各サービスの完成基準は **「主要技術課題が動く形で示せていること」** に固定してある。具体的には:

- ローカルで起動でき、主要ユースケースが動くこと
- 技術課題（fan-out / 状態機械 / 整合性 / 権限グラフ など）がコードから読み取れること
- README にアーキ図 / 起動手順、ADR 最低 3 本、CI に lint と test
- E2E (Playwright) で主要シナリオを動画キャプチャ

**「機能が網羅されていること」は完成基準に入っていない**。たとえば slack はファイル添付・スレッド・絵文字リアクションを作っていない。それは「WebSocket fan-out / 既読 cursor 整合性」という主要課題と関係ないから。

機能を増やす方向の誘惑は強いが、**「技術課題の理解が深まるか」で判定し、深まらないなら作らない**。スコープから何を捨てたかは [`docs/service-architecture-lab-policy.md`](service-architecture-lab-policy.md) の「スコープ判定」節を参照。

---

## 5. 読み方（時間予算別）

| 予算 | おすすめの入り口 |
| --- | --- |
| **3 分** | ルート README の **「プロジェクト横断のハイライト」** 節 — API スタイル / キュー / 認可 / モノリス境界 / 整合性パターンの 5 つの対比表 |
| **15 分** | 興味のある技術課題に該当するサービスの `architecture.md` を 1 本 — 例: リアルタイム配信なら [`slack/docs/architecture.md`](../slack/docs/architecture.md) または [`discord/docs/architecture.md`](../discord/docs/architecture.md) |
| **30 分** | [`shopify/`](../shopify/) または [`perplexity/`](../perplexity/) の `architecture.md` + ADR 全本 — 設計判断の密度が一番濃い 2 サービス |
| **設計思想を先に** | このページ + [`docs/service-architecture-lab-policy.md`](service-architecture-lab-policy.md)（完成定義・スコープ判定・ADR 運用） |
| **判断ログを通読** | [`docs/adr-index.md`](adr-index.md) — 9 サービスの ADR 40 本をテーマ別 / サービス別 2 軸で索引化 |
| **横断知見だけ拾う** | [`docs/coding-rules/`](coding-rules/)・[`docs/operating-patterns.md`](operating-patterns.md)・[`docs/api-style.md`](api-style.md)・[`docs/testing-strategy.md`](testing-strategy.md) — 9 サービスを通じて踏んだ落とし穴を共通ルール化したもの |

---

## 6. 失敗・宿題・反省も読み所

成功例だけが並ぶポートフォリオは説得力が低い。各サービスの `architecture.md` 末尾には可能な限り

- **採用しなかった選択肢**と理由
- **踏んだ落とし穴**
- **もう一度作るなら変える点**
- **残した宿題**（時間 / スコープ判断で意図的に捨てたもの）

を残している。書式は [`docs/learning-log-template.md`](learning-log-template.md)。

「網羅されていない」「妥協した」「次はこう変える」というセクションこそ、設計プロセスの真の解像度が出るところなので、可能ならここまで読んでもらいたい。

---

## 7. リポジトリの主要ドキュメント

| ファイル | 役割 |
| --- | --- |
| [`docs/service-architecture-lab-policy.md`](service-architecture-lab-policy.md) | 完成の定義 / スコープ判定 / ADR 運用 / プロジェクト一覧（詳細） |
| [`docs/adr-template.md`](adr-template.md) | ADR の書式 |
| [`docs/adr-index.md`](adr-index.md) | 全 9 サービスの ADR 40 本を横断索引 |
| [`docs/learning-log-template.md`](learning-log-template.md) | 各サービスの「学びログ」セクション雛形 |
| [`docs/api-style.md`](api-style.md) | REST + OpenAPI / GraphQL / SSE / 内部 ingress の選定軸 |
| [`docs/coding-rules/`](coding-rules/) | rails / python / go / frontend の規約と落とし穴集 |
| [`docs/framework-django-vs-rails.md`](framework-django-vs-rails.md)・[`docs/framework-python-async-vs-sync.md`](framework-python-async-vs-sync.md) | フレームワーク選定の比較記録 |
| [`docs/operating-patterns.md`](operating-patterns.md) | 9 サービスで確立した運用パターン |
| [`docs/testing-strategy.md`](testing-strategy.md) | 各プロジェクトのテスト方針と CI 構成 |
| [`docs/git-workflow.md`](git-workflow.md) | ブランチ / コミット規約 |
| [`docs/design-tokens.md`](design-tokens.md) | 全プロジェクト共通の design tokens |
| [`CLAUDE.md`](../CLAUDE.md) | エージェント向け要約（人間が読む場合は policy.md と本ページが上位） |
