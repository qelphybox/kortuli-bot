RSpec.describe Booking::Web::InitData do
  # Telegram signs initData with a key derived from the bot token, so a valid
  # payload proves the person on the other end really came through Telegram.
  # This vector was produced with the openssl CLI rather than with this code,
  # so the expectation has an independent source: if the implementation drifts
  # from Telegram's algorithm, this fails.
  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:user_json) { '{"id":42,"first_name":"Kirill","username":"qelphybox","language_code":"ru"}' }
  let(:signed) do
    "query_id=AAHdF6IQAAAAAN0XohDhrOrc" \
      "&user=%7B%22id%22%3A42%2C%22first_name%22%3A%22Kirill%22%2C%22username%22%3A%22qelphybox%22%2C%22language_code%22%3A%22ru%22%7D" \
      "&auth_date=1785000000" \
      "&hash=7b6e9b4c440bd3fd3e0ca50d3b48b5e96dfa64daa869e9b170ea06cf0477b313"
  end
  # The vector's own auth_date, so "recent enough" is decided by the example
  # rather than by the calendar.
  let(:signed_at) { Time.at(1_785_000_000).utc }

  it "accepts a payload Telegram signed and reports who sent it" do
    result = described_class.verify(signed, token:, now: signed_at)

    expect(result).to eq(42)
  end

  it "rejects a payload whose signature is for a different token" do
    result = described_class.verify(signed, token: "999999:SOME-OTHER-TOKEN", now: signed_at)

    expect(result).to be_nil
  end

  # The whole point of the signature: a tampered field must invalidate it.
  # Swapping the user id is the tamper that matters — it is how one person
  # would act as another.
  it "rejects a payload whose user was swapped after signing" do
    tampered = signed.sub("%22id%22%3A42", "%22id%22%3A43")

    expect(described_class.verify(tampered, token:, now: signed_at)).to be_nil
  end

  it "rejects a payload carrying no signature at all" do
    expect(described_class.verify("user=%7B%22id%22%3A42%7D", token:, now: signed_at)).to be_nil
  end

  it "rejects nonsense that is not a query string" do
    expect(described_class.verify("", token:, now: signed_at)).to be_nil
    expect(described_class.verify(nil, token:, now: signed_at)).to be_nil
  end

  # initData is issued once when the app opens and never refreshed, so a stale
  # one is a replay rather than a live visitor.
  it "rejects a signature older than the window we trust" do
    a_day_late = signed_at + Booking::Web::InitData::MAX_AGE_SECONDS + 1

    expect(described_class.verify(signed, token:, now: a_day_late)).to be_nil
  end

  it "accepts one that is old but still inside the window" do
    just_in_time = signed_at + Booking::Web::InitData::MAX_AGE_SECONDS - 1

    expect(described_class.verify(signed, token:, now: just_in_time)).to eq(42)
  end
end
