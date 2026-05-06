# frozen_string_literal: true
# Mock 3rd-party App receiver (ADR 0004 demo).
#
# 役割:
#   - Rails backend が POST する webhook を受信し、HMAC を検証して in-memory に積む
#   - "/" の Web UI が 1s polling で受信ログを表示する → playwright gif 用
#
# 検証する不変条件:
#   1. X-Hmac-Sha256 が body の HMAC-SHA256(secret) と一致する
#   2. 同じ X-Webhook-Delivery-Id は 2 度処理しない (受信側冪等性 / ADR 0004)
#
# 起動: bundle exec ruby app.rb -p 4000

require "sinatra/base"
require "json"
require "openssl"
require "base64"
require "time"

class MockReceiver < Sinatra::Base
  SECRET = ENV.fetch("DEMO_APP_SECRET", "demo-shared-secret-do-not-use-in-prod")

  # in-memory state (process restart で消えてよい)
  @@deliveries = []
  @@seen_ids = {}
  @@mutex = Mutex.new

  set :port, ENV.fetch("PORT", 4000).to_i
  set :bind, ENV.fetch("BIND", "0.0.0.0")
  set :show_exceptions, false

  helpers do
    # Rails 側 Apps::Signer と一致させる: HMAC-SHA256 → base64 strict (Shopify 形式)
    def hmac_b64(body)
      Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", SECRET, body))
    end
  end

  # ---------- ingest ----------

  post "/webhooks/shopify" do
    body = request.body.read
    sig  = request.env["HTTP_X_HMAC_SHA256"].to_s
    did  = request.env["HTTP_X_WEBHOOK_DELIVERY_ID"].to_s
    topic = request.env["HTTP_X_WEBHOOK_TOPIC"].to_s
    expected = hmac_b64(body)

    verified = !sig.empty? && Rack::Utils.secure_compare(sig, expected)

    @@mutex.synchronize do
      duplicate = @@seen_ids.key?(did)
      @@seen_ids[did] = true unless did.empty?

      @@deliveries.unshift(
        delivery_id: did,
        topic: topic,
        verified: verified,
        duplicate: duplicate,
        received_at: Time.now.iso8601(3),
        body: safe_parse(body)
      )
      @@deliveries = @@deliveries.first(50)
    end

    halt 401, { "Content-Type" => "application/json" }, JSON.dump(error: "bad_hmac") unless verified

    status 200
    content_type :json
    JSON.dump(ok: true, delivery_id: did, duplicate: !!@@seen_ids[did] && @@deliveries[0][:duplicate])
  end

  # ---------- read API ----------

  get "/api/deliveries" do
    content_type :json
    JSON.dump(@@mutex.synchronize { @@deliveries.dup })
  end

  post "/api/reset" do
    @@mutex.synchronize { @@deliveries.clear; @@seen_ids.clear }
    status 204
  end

  # ---------- UI ----------

  get "/" do
    content_type :html
    HTML_PAGE
  end

  private

  def safe_parse(body)
    JSON.parse(body)
  rescue JSON::ParserError
    body.to_s[0, 500]
  end

  HTML_PAGE = <<~HTML
    <!doctype html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <title>Mock 3rd-party App receiver</title>
      <style>
        :root { color-scheme: light; }
        body { font: 14px/1.5 -apple-system, system-ui, sans-serif; margin: 0; padding: 24px; background: #fafafa; color: #111; }
        h1 { font-size: 18px; margin: 0 0 4px; letter-spacing: -0.01em; }
        .sub { color: #666; font-size: 12px; margin-bottom: 16px; }
        .empty { color: #999; padding: 40px; text-align: center; border: 1px dashed #ddd; border-radius: 8px; background: #fff; }
        .row { background: #fff; border: 1px solid #e5e5e5; border-radius: 8px; padding: 12px 14px; margin-bottom: 8px; }
        .head { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
        .topic { font-weight: 600; font-family: ui-monospace, Menlo, monospace; font-size: 12px; }
        .badge { font-size: 11px; padding: 2px 6px; border-radius: 4px; font-weight: 600; }
        .ok { background: #e6f7e9; color: #117a2c; }
        .bad { background: #fde8e8; color: #b42318; }
        .dup { background: #fff4d6; color: #8a5a00; }
        .ts { color: #999; font-size: 11px; margin-left: auto; font-variant-numeric: tabular-nums; }
        .did { color: #666; font-family: ui-monospace, Menlo, monospace; font-size: 11px; }
        pre { background: #0f1419; color: #e6e6e6; padding: 10px; border-radius: 6px; font-size: 12px; overflow-x: auto; margin: 6px 0 0; }
      </style>
    </head>
    <body>
      <h1>Mock 3rd-party App receiver</h1>
      <div class="sub">port :4000 — listens on /webhooks/shopify (HMAC + delivery_id idempotency)</div>
      <div id="list" class="empty">no webhooks received yet</div>
      <script>
        async function tick() {
          try {
            const r = await fetch('/api/deliveries');
            const items = await r.json();
            const list = document.getElementById('list');
            if (!items.length) { list.className = 'empty'; list.textContent = 'no webhooks received yet'; return; }
            list.className = '';
            list.innerHTML = items.map(d => {
              const badges = [];
              badges.push(d.verified
                ? '<span class="badge ok">HMAC verified</span>'
                : '<span class="badge bad">HMAC FAIL</span>');
              if (d.duplicate) badges.push('<span class="badge dup">duplicate (idempotent skip)</span>');
              const body = JSON.stringify(d.body, null, 2);
              return `<div class="row">
                <div class="head">
                  <span class="topic">${d.topic || '(no topic)'}</span>
                  ${badges.join('')}
                  <span class="ts">${d.received_at}</span>
                </div>
                <div class="did">delivery_id: ${d.delivery_id || '(missing)'}</div>
                <pre>${escapeHtml(body)}</pre>
              </div>`;
            }).join('');
          } catch (_) {}
        }
        function escapeHtml(s){return s.replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
        tick();
        setInterval(tick, 1000);
      </script>
    </body>
    </html>
  HTML
end

if $PROGRAM_NAME == __FILE__
  MockReceiver.run!
end
