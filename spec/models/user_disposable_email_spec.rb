require "rails_helper"

# Front-door spam defense: disposable/throwaway email domains are rejected at
# self-signup (web and mobile both go through User#save). See
# DisposableEmailValidator.
RSpec.describe "User disposable-email guard", type: :model do
  let(:operator) { create(:operator) }

  it "rejects a known disposable email domain at signup" do
    user = build(:user, operator: operator, email: "spammer@mailinator.com")
    expect(user).not_to be_valid
    expect(user.errors[:email].join).to match(/temporary email/i)
  end

  it "rejects a subdomain of a disposable domain" do
    user = build(:user, operator: operator, email: "x@inbox.guerrillamail.com")
    user.valid?
    expect(user.errors[:email].join).to match(/temporary email/i)
  end

  it "allows a normal email domain" do
    user = build(:user, operator: operator, email: "real.person@gmail.com")
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "does not block admin-created members (a walk-in an admin adds by hand)" do
    user = build(:user, operator: operator, email: "walkin@mailinator.com", admin_created: true)
    user.valid?
    expect(user.errors[:email]).to be_empty
  end

  it "only runs on create — never re-blocks an existing member on update" do
    user = create(:user, operator: operator, email: "real@gmail.com")
    user.email = "later@mailinator.com"
    user.valid? # :update context
    expect(user.errors[:email]).to be_empty
  end
end
