RSpec.describe Booking::Web::Session do
  subject(:sessions) { described_class.new(secret: "a-secret-that-only-the-server-knows") }

  let(:issued_at) { Time.utc(2026, 7, 27, 12, 0, 0) }

  it "reads back the visitor it was issued for" do
    token = sessions.issue(42, now: issued_at)

    expect(sessions.user_id(token, now: issued_at)).to eq(42)
  end

  it "refuses a token signed with somebody else's secret" do
    forged = described_class.new(secret: "not-the-server-secret").issue(42, now: issued_at)

    expect(sessions.user_id(forged, now: issued_at)).to be_nil
  end

  # The whole reason the cookie is signed: otherwise anyone could edit the user
  # id in it and read another person's Watches.
  it "refuses a token whose visitor was edited" do
    token = sessions.issue(42, now: issued_at)
    edited = token.sub("42", "43")

    expect(sessions.user_id(edited, now: issued_at)).to be_nil
  end

  it "refuses a token that has expired" do
    token = sessions.issue(42, now: issued_at)
    too_late = issued_at + described_class::LIFETIME_SECONDS + 1

    expect(sessions.user_id(token, now: too_late)).to be_nil
  end

  it "still accepts a token inside its lifetime" do
    token = sessions.issue(42, now: issued_at)
    later = issued_at + described_class::LIFETIME_SECONDS - 1

    expect(sessions.user_id(token, now: later)).to eq(42)
  end

  describe ".for_token" do
    let(:token) { "123456:bot-token" }

    # A deploy restarts the web process; cookies issued before it must still
    # read after it, or every deploy would bounce everyone through /start.
    it "derives the same key from the same token" do
      cookie = described_class.for_token(token).issue(42, now: issued_at)

      expect(described_class.for_token(token).user_id(cookie, now: issued_at)).to eq(42)
    end

    # Rotating the bot token is the one way to log everyone out.
    it "refuses a cookie issued under a different token" do
      cookie = described_class.for_token("654321:old-token").issue(42, now: issued_at)

      expect(described_class.for_token(token).user_id(cookie, now: issued_at)).to be_nil
    end

    # The token itself must not be the key: then a cookie signature would be
    # one HMAC away from anything else keyed on the raw token.
    it "does not sign with the raw token" do
      cookie = described_class.new(secret: token).issue(42, now: issued_at)

      expect(described_class.for_token(token).user_id(cookie, now: issued_at)).to be_nil
    end
  end

  it "refuses junk" do
    expect(sessions.user_id(nil, now: issued_at)).to be_nil
    expect(sessions.user_id("", now: issued_at)).to be_nil
    expect(sessions.user_id("not.a.token", now: issued_at)).to be_nil
  end
end
