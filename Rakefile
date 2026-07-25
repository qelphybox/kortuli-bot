begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  # The production image is bundled without the test group. Losing `rake spec`
  # there is fine; losing the whole Rakefile to a require error is not.
end

# Loaded per-task rather than at the top, so `rake spec` and `rake -T` stay out
# of the database. Mirrors bin/bot: a local .env if there is one, the
# container's environment otherwise.
def boot!
  begin
    require "dotenv/load"
  rescue LoadError
    # Not installed in production, where the gem would have nothing to read.
  end
  require_relative "lib/booking"
end

desc "Create or migrate the database"
task :migrate do
  boot!
  Booking::DB.connection
  puts "migrated: #{Booking::Config.database_url}"
end

desc "Mirror config/clubs.yml into the database"
task seed: :migrate do
  boot!
  repos = Booking::Repos.for(Booking::DB.connection)
  clubs = Booking::ClubRegistry.sync_from_config!(repos.clubs)
  clubs.each { puts "#{_1.slug}  #{_1.name}  (#{_1.enabled? ? "enabled" : "disabled"})" }
end

desc "Poll every club once, in the foreground, without starting the bot"
task poll: :seed do
  boot!
  repos = Booking::Repos.for(Booking::DB.connection)
  notifier = Struct.new(:sent) do
    def deliver(candidates)
      candidates.each { puts "  would notify #{_1.watch.user_id}: #{_1.slot.court_label} #{_1.slot.local_starts_at}" }
      candidates.size
    end
  end.new
  Booking::Poller.new(repos:, notifier:, http: Booking::Http.new).tick
end

namespace :discover do
  desc "Find the ids needed for a Reservio club: rake 'discover:reservio[padel-club2]'"
  task :reservio, [:subdomain] do |_, args|
    boot!
    subdomain = args[:subdomain] or abort "usage: rake 'discover:reservio[subdomain]'"

    http = Booking::Http.new
    page = http.get_body("https://#{subdomain}.reservio.com/")
    business_id = page[/"businessId":"([a-f0-9-]{36})"/, 1] or abort "no businessId on that page"

    services = http.get_json("#{Booking::Adapters::Reservio::BASE_URL}/businesses/#{business_id}/services")
    courts = http.get_json("#{Booking::Adapters::Reservio::BASE_URL}/businesses/#{business_id}/resources")

    puts "business_id: #{business_id}"
    puts "services:"
    services.fetch("data").each { puts "  #{_1["id"]}  #{_1.dig("attributes", "name")}  #{_1.dig("attributes", "cost")}" }
    puts "courts:"
    courts.fetch("data").each { puts "  #{_1["id"]}  #{_1.dig("attributes", "name")}" }
  end
end
