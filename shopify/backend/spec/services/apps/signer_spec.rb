require "rails_helper"

RSpec.describe Apps::Signer do
  let(:secret) { "supersecret-1234567890" }
  let(:body) { %({"order_id":42}) }

  it "署名は再現可能で、tampered body だと一致しない" do
    sig = described_class.sign(secret: secret, body: body)
    expect(sig).to eq(described_class.sign(secret: secret, body: body))
    expect(described_class.verify(secret: secret, body: body, signature: sig)).to be(true)

    expect(described_class.verify(secret: secret, body: body + " ", signature: sig)).to be(false)
  end

  it "別の secret では verify が失敗する" do
    sig = described_class.sign(secret: secret, body: body)
    expect(described_class.verify(secret: "different", body: body, signature: sig)).to be(false)
  end
end
