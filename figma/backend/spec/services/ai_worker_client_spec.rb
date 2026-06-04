require "rails_helper"

# ADR 0003 / operating-patterns: ai-worker 不通時の graceful degradation を縛る。
RSpec.describe AiWorkerClient do
  it "ai-worker 不通時は例外を投げず default + degraded:true を返す" do
    # 到達不能ポートに向ける → HTTPX::ErrorResponse (接続拒否) を degrade で吸収。
    allow(described_class).to receive(:base_url).and_return("http://127.0.0.1:1")

    lint = described_class.lint(objects: [], grid: 8)
    expect(lint["degraded"]).to be(true)
    expect(lint["issues"]).to eq([])

    layout = described_class.auto_layout(objects: [], mode: "align-left")
    expect(layout["degraded"]).to be(true)
    expect(layout["updates"]).to eq([])
  end
end
