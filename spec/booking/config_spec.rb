RSpec.describe Booking::Config do
  describe ".missing_environment" do
    around do |example|
      saved = ENV.to_h.slice("TELEGRAM_TOKEN", "BOT_USERNAME")
      example.run
    ensure
      %w[TELEGRAM_TOKEN BOT_USERNAME].each { ENV.delete(_1) }
      ENV.update(saved)
    end

    it "names what is unset" do
      ENV.delete("TELEGRAM_TOKEN")
      ENV["BOT_USERNAME"] = "kortuli_bot"

      expect(described_class.missing_environment(%w[TELEGRAM_TOKEN BOT_USERNAME])).to eq(%w[TELEGRAM_TOKEN])
    end

    # `KEY=` in a .env, or a secret Kamal expanded from an unset variable,
    # arrives as "" — set, but no more usable than absent.
    it "counts an empty value as missing" do
      ENV["TELEGRAM_TOKEN"] = ""
      ENV["BOT_USERNAME"] = "kortuli_bot"

      expect(described_class.missing_environment(%w[TELEGRAM_TOKEN BOT_USERNAME])).to eq(%w[TELEGRAM_TOKEN])
    end
  end

  describe ".padel_academy_credentials" do
    around do |example|
      saved = ENV.to_h.slice("PADEL_ACADEMY_EMAIL", "PADEL_ACADEMY_PASSWORD")
      example.run
    ensure
      %w[PADEL_ACADEMY_EMAIL PADEL_ACADEMY_PASSWORD].each { ENV.delete(_1) }
      ENV.update(saved)
    end

    it "pairs the two when both are set" do
      ENV["PADEL_ACADEMY_EMAIL"] = "bot@example.test"
      ENV["PADEL_ACADEMY_PASSWORD"] = "secret"

      expect(described_class.padel_academy_credentials).to eq(email: "bot@example.test", password: "secret")
    end

    # Half a login is no login; Kamal hands an unset secret over as "".
    it "is nil when either is missing or empty" do
      ENV["PADEL_ACADEMY_EMAIL"] = "bot@example.test"
      ENV["PADEL_ACADEMY_PASSWORD"] = ""

      expect(described_class.padel_academy_credentials).to be_nil
    end
  end
end
