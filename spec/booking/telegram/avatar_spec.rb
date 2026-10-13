require "tmpdir"

RSpec.describe Booking::Telegram::Avatar do
  subject(:avatar) { described_class.new(api:, path:, stamp:, logger:) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "avatar.jpg").tap { File.binwrite(_1, "first face") } }
  let(:stamp) { File.join(dir, "data", "avatar.sha256") }
  let(:api) { FakeAvatarApi.new }
  let(:logged) { [] }
  let(:logger) { ->(line) { logged << line } }

  after { FileUtils.remove_entry(dir) }

  # Stands in for Telegram::Bot::Api: records every upload, and can be told
  # to refuse them.
  class FakeAvatarApi
    attr_reader :uploads

    def initialize(refuse: false)
      @uploads = []
      @refuse = refuse
    end

    def set_my_profile_photo(photo:, **files)
      raise "Too Many Requests" if @refuse

      @uploads << { photo:, files: }
      true
    end
  end

  it "uploads the photo as a fresh file, the only way Telegram takes one" do
    avatar.install

    expect(api.uploads.size).to eq(1)
    upload = api.uploads.first
    expect(upload[:photo].to_h).to eq(type: "static", photo: "attach://avatar")
    expect(upload[:files][:avatar].content_type).to eq("image/jpeg")
    expect(logged).to eq(["telegram: profile photo set"])
  end

  # The bot restarts on every deploy, and every upload is a new photo.
  it "uploads nothing it has uploaded before" do
    avatar.install
    avatar.install

    expect(api.uploads.size).to eq(1)
    expect(logged.last).to eq("telegram: profile photo unchanged")
  end

  it "uploads again once the file changes" do
    avatar.install
    File.binwrite(path, "second face")
    avatar.install

    expect(api.uploads.size).to eq(2)
  end

  # A refused upload is not remembered as done, so the next boot tries again.
  it "keeps going when Telegram refuses, and tries again next time" do
    described_class.new(api: FakeAvatarApi.new(refuse: true), path:, stamp:, logger:).install
    avatar.install

    expect(logged.first).to match(/could not set the profile photo — RuntimeError/)
    expect(api.uploads.size).to eq(1)
  end

  # Telegram takes a static profile photo as a JPEG and nothing else.
  it "ships a JPEG" do
    expect(File.binread(Booking::Config.avatar_file, 3).bytes).to eq([0xFF, 0xD8, 0xFF])
  end
end
