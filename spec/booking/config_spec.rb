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
end
