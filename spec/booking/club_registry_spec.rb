require "tmpdir"

RSpec.describe Booking::ClubRegistry do
  let(:clubs) { Booking::Repo::Clubs.new(Booking::DB.connect("sqlite:/")) }

  def sync(*slugs)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "clubs.yml")
      File.write(path, YAML.dump(slugs.map { { "slug" => _1, "name" => _1, "adapter" => "reservio" } }))
      described_class.sync_from_config!(clubs, path)
    end
  end

  it "mirrors every entry into the database, enabled" do
    sync("club-a", "club-b")

    expect(clubs.enabled.map(&:slug)).to eq(%w[club-a club-b])
  end

  it "disables a club that has been deleted from config rather than polling it forever" do
    sync("club-a", "club-b")
    sync("club-b")

    expect(clubs.enabled.map(&:slug)).to eq(%w[club-b])
    expect(clubs.find("club-a")).not_to be_enabled
  end

  it "enables a club again once it is back in config" do
    sync("club-a")
    sync
    sync("club-a")

    expect(clubs.find("club-a")).to be_enabled
  end
end
