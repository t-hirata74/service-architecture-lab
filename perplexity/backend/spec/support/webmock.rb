# ADR 0005: ai-worker への HTTP 呼び出しは WebMock で stub する.
# ローカルホストへの allow は不要 (ai-worker は WebMock で完全 stub する方針).
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: false)
