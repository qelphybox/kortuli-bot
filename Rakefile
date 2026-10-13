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

namespace :sapadelo do
  desc "Refresh config/club_profiles.yml from sapadelo.com, for every club that names its page there"
  task :import do
    boot!
    require "yaml"

    http = Booking::Http.new
    linked = YAML.safe_load_file(Booking::Config.clubs_file).filter_map do |entry|
      theirs = entry.dig("settings", "sapadelo")
      [entry.fetch("slug"), theirs] if theirs
    end
    areas = Booking::Sapadelo.areas(http.get_body(Booking::Sapadelo::CITY_URL))

    profiles = linked.to_h do |slug, theirs|
      # A directory, not a booking system: one page a second is plenty.
      sleep 1
      url = Booking::Sapadelo.club_url(theirs)
      profile = Booking::Sapadelo.profile(http.get_body(url), source: url, area: areas[theirs])
      puts "#{slug}  #{profile.fetch("courts").size} courts  #{profile.dig("hours", "mon") || "no hours"}  #{profile["area"]}"
      [slug, profile]
    end

    path = Booking::Config.club_profiles_file
    File.write(path, <<~YAML + YAML.dump({ "checked_on" => Date.today.iso8601, "clubs" => profiles }).delete_prefix("---\n"))
      # Written by `bundle exec rake sapadelo:import` — edit config/clubs.yml
      # (settings.sapadelo) and run it again rather than editing this by hand.
      #
      # Each club's Profile: the cover over every court, where it is, and the
      # hours and prices it lists on sapadelo.com. For people to read; nothing
      # that decides a Cell looks at it.
    YAML
    puts "wrote #{profiles.size} profiles to #{path}"
  end
end

namespace :discover do
  desc "Find the ids needed for a Reservio club: rake 'discover:reservio[padel-port-batumi2]'"
  task :reservio, [:subdomain] do |_, args|
    boot!
    subdomain = args[:subdomain] or abort "usage: rake 'discover:reservio[subdomain]'"

    http = Booking::Http.new
    page = http.get_body("https://#{subdomain}.reservio.com/")
    business_id = page[/"businessId":"([a-f0-9-]{36})"/, 1] or abort "no businessId on that page"

    base = "#{Booking::Adapters::Reservio::BASE_URL}/businesses/#{business_id}"
    business = http.get_json(base).fetch("data").fetch("attributes")
    # Included so each service names the courts it books — one service over
    # every court, or one per court, is what decides `service_ids`.
    services = http.get_json("#{base}/services", { "include" => "resources" })
    courts = services.fetch("included", []).select { _1["type"] == "resource" }.to_h { [_1["id"], _1.dig("attributes", "name")] }
    hours = http.get_json("#{base}/opening-hours").fetch("data")
    clock = ->(seconds) { format("%02d:%02d", seconds / 3600, seconds % 3600 / 60) }
    week = %w[mo tu we th fr sa su]

    puts "business_id: #{business_id}  (#{business["name"]})"
    # Past this the source answers with nothing at all, so it is the club's
    # own window; `max_days` counts today as well.
    ahead = business.dig("settings", "reservationsLaterThan").to_i / 86_400
    puts "window: #{ahead} days ahead, so max_days: #{ahead + 1}"
    puts "services (for service_ids), each with the courts it books:"
    services.fetch("data").each do |service|
      booked = service.dig("relationships", "resources", "data").to_a.map { courts.fetch(_1["id"], _1["id"]) }
      puts "  #{service["id"]}  #{service.dig("attributes", "name")}  #{service.dig("attributes", "cost")}  -> #{booked.join(", ")}"
    end
    # The business's own hours. A court can carry narrower ones of its own;
    # those are skipped, because opening_hours is declared per club.
    puts "opening hours:"
    hours.reject { _1.dig("relationships", "resource", "data") }
         .group_by { [_1.dig("attributes", "start"), _1.dig("attributes", "end")] }.sort
         .each { |(from, to), rows| puts "  #{clock.(from)}–#{clock.(to)}  #{(week & rows.flat_map { _1.dig("attributes", "days") }).join(" ")}" }
  end
end
