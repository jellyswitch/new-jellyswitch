require "rails_helper"

# Front-door spam defense: reject self-signups whose email domain can't
# receive mail (no MX, no A/AAAA fallback) — catches typo/fake domains like
# "user@gmial.con". Network-gated behind ENV["VALIDATE_EMAIL_MX"] so the test
# suite (and dev) never hit real DNS, and FAIL-OPEN so a DNS hiccup can never
# block a real signup. See MxRecordValidator.
RSpec.describe "User MX-record guard", type: :model do
  let(:operator) { create(:operator) }

  # Force the validator on and stub the resolver so no real DNS call happens.
  def stub_dns(mx: [], a: [], aaaa: [], raises: nil)
    allow(MxRecordValidator).to receive(:enabled?).and_return(true)
    if raises
      allow(Resolv::DNS).to receive(:open).and_raise(raises)
      return
    end
    resolver = instance_double(Resolv::DNS)
    allow(resolver).to receive(:timeouts=)
    allow(resolver).to receive(:getresources)
      .with(anything, Resolv::DNS::Resource::IN::MX).and_return(mx)
    allow(resolver).to receive(:getresources)
      .with(anything, Resolv::DNS::Resource::IN::A).and_return(a)
    allow(resolver).to receive(:getresources)
      .with(anything, Resolv::DNS::Resource::IN::AAAA).and_return(aaaa)
    allow(Resolv::DNS).to receive(:open).and_yield(resolver)
  end

  it "accepts a domain that has an MX record" do
    stub_dns(mx: [double("mx")])
    user = build(:user, operator: operator, email: "real@gmail.com")
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "accepts a domain with no MX but an A record (RFC 5321 implicit MX)" do
    stub_dns(mx: [], a: [double("a")])
    user = build(:user, operator: operator, email: "real@a-only.example")
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "rejects a domain with no MX and no A/AAAA record" do
    stub_dns(mx: [], a: [], aaaa: [])
    user = build(:user, operator: operator, email: "ghost@nodomainhere.invalid")
    expect(user).not_to be_valid
    expect(user.errors[:email].join).to match(/can't receive email|valid email/i)
  end

  it "FAILS OPEN when the DNS lookup errors (never blocks a real signup)" do
    stub_dns(raises: Resolv::ResolvError)
    user = build(:user, operator: operator, email: "real@dns-hiccup.example")
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "FAILS OPEN when the DNS lookup times out" do
    stub_dns(raises: Timeout::Error)
    user = build(:user, operator: operator, email: "real@slow-dns.example")
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "does NOT run when disabled (default) — no DNS call, signup passes" do
    # enabled? defaults false; if it tried DNS, this unstubbed call would prove it.
    expect(Resolv::DNS).not_to receive(:open)
    user = build(:user, operator: operator, email: "ghost@nodomainhere.invalid")
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "does not block admin-created members (a walk-in an admin adds by hand)" do
    stub_dns(mx: [], a: [], aaaa: [])
    user = build(:user, operator: operator, email: "walkin@nodomainhere.invalid", admin_created: true)
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "only runs on create — never re-blocks an existing member on update" do
    stub_dns(mx: [double("mx")])
    user = create(:user, operator: operator, email: "real@gmail.com")
    stub_dns(mx: [], a: [], aaaa: [])
    user.email = "later@nodomainhere.invalid"
    user.valid? # :update context
    expect(user.errors[:email]).to be_empty
  end
end
