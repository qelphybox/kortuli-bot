module Booking
  module Telegram
    # The step-by-step watch builder, as a pure state machine.
    #
    # It knows nothing about Telegram: no bot, no API calls, no message ids. It
    # takes the string a button carries and returns the next draft plus what to
    # render. That keeps the conversational logic — the one genuinely stateful
    # thing in the bot — out of the handlers and under test.
    class Wizard
      PREFIX = "w".freeze
      HOURS = (6..23).freeze
      LAST_HOUR = 24
      MONDAY_FIRST = [1, 2, 3, 4, 5, 6, 0].freeze
      BUTTONS_PER_ROW = 4

      Button = Data.define(:text, :data)
      View = Data.define(:text, :keyboard)
      Draft = Data.define(:step, :club_slugs, :weekdays, :from_minute, :to_minute)
      Outcome = Data.define(:draft, :status, :alert)

      class << self
        def begin
          Draft.new(step: :clubs, club_slugs: [], weekdays: [], from_minute: nil, to_minute: nil)
        end

        def apply(draft, callback, clubs:)
          action = callback.action
          return ignored(draft) unless callback.prefix == PREFIX
          return Outcome.new(draft:, status: :cancelled, alert: nil) if action == "cancel"

          # A button from a step the user has already left is stale, not an
          # error: an old message is still on screen and got tapped.
          case [draft.step, action]
          in [:clubs, "club"] then toggle_club(draft, callback.value, clubs)
          in [:clubs, "next"] then leave_clubs(draft)
          in [:days, "day"] then toggle_day(draft, callback.value)
          in [:days, "next"] then leave_days(draft)
          in [:from, "from"] then set_from(draft, callback.value)
          in [:to, "to"] then set_to(draft, callback.value)
          else ignored(draft)
          end
        end

        def view(draft, clubs:)
          case draft.step
          when :clubs then View.new(text: Messages.pick_clubs, keyboard: club_keyboard(draft, clubs))
          when :days then View.new(text: Messages.pick_days, keyboard: day_keyboard(draft))
          when :from then View.new(text: Messages.pick_from, keyboard: hour_keyboard("from", HOURS))
          when :to then View.new(text: Messages.pick_to(draft.from_minute), keyboard: hour_keyboard("to", closing_hours(draft)))
          end
        end

        private

        def continue(draft) = Outcome.new(draft:, status: :continue, alert: nil)
        def ignored(draft) = Outcome.new(draft:, status: :ignored, alert: nil)
        def refuse(draft, alert) = Outcome.new(draft:, status: :continue, alert:)

        def toggle_club(draft, slug, clubs)
          return ignored(draft) unless clubs.any? { _1.slug == slug }

          continue(draft.with(club_slugs: toggle(draft.club_slugs, slug)))
        end

        def toggle_day(draft, value)
          day = Integer(value, exception: false)
          return ignored(draft) unless day && (0..6).cover?(day)

          continue(draft.with(weekdays: toggle(draft.weekdays, day)))
        end

        def toggle(collection, member)
          collection.include?(member) ? collection - [member] : collection + [member]
        end

        def leave_clubs(draft)
          return refuse(draft, Messages.pick_at_least_one_club) if draft.club_slugs.empty?

          continue(draft.with(step: :days))
        end

        def leave_days(draft)
          return refuse(draft, Messages.pick_at_least_one_day) if draft.weekdays.empty?

          continue(draft.with(step: :from))
        end

        def set_from(draft, value)
          hour = Integer(value, exception: false)
          return ignored(draft) unless hour && HOURS.cover?(hour)

          continue(draft.with(from_minute: hour * 60, step: :to))
        end

        def set_to(draft, value)
          hour = Integer(value, exception: false)
          # Guard rather than trust the keyboard: the button that produced this
          # may have been rendered before the opening hour changed. Asking the
          # same method the keyboard asked is what keeps the two answers equal.
          return ignored(draft) unless hour && closing_hours(draft).cover?(hour)

          Outcome.new(draft: draft.with(to_minute: hour * 60), status: :finished, alert: nil)
        end

        def closing_hours(draft) = (((draft.from_minute / 60) + 1)..LAST_HOUR)

        def club_keyboard(draft, clubs)
          return [[cancel_button]] if clubs.empty?

          rows = clubs.map { [Button.new(text: check(draft.club_slugs.include?(_1.slug), _1.name), data: Callback.build(PREFIX, "club", _1.slug))] }
          rows + [[next_button, cancel_button]]
        end

        def day_keyboard(draft)
          buttons = MONDAY_FIRST.map do |day|
            Button.new(text: check(draft.weekdays.include?(day), Messages::DAY_NAMES[day]), data: Callback.build(PREFIX, "day", day))
          end
          buttons.each_slice(BUTTONS_PER_ROW).to_a + [[next_button, cancel_button]]
        end

        def hour_keyboard(kind, hours)
          buttons = hours.map { Button.new(text: Messages.clock(_1 * 60), data: Callback.build(PREFIX, kind, _1)) }
          buttons.each_slice(BUTTONS_PER_ROW).to_a + [[cancel_button]]
        end

        def check(selected, label) = selected ? "✅ #{label}" : label
        def next_button = Button.new(text: "Next ▶", data: Callback.build(PREFIX, "next"))
        def cancel_button = Button.new(text: "Cancel", data: Callback.build(PREFIX, "cancel"))
      end

      # Drafts live in memory only: a half-finished form is worth less than the
      # bookkeeping to persist it, and a restart just means tapping /watch again.
      class Store
        def initialize
          @drafts = {}
          @lock = Mutex.new
        end

        def fetch(user_id) = @lock.synchronize { @drafts[user_id] }
        def put(user_id, draft) = @lock.synchronize { @drafts[user_id] = draft }
        def delete(user_id) = @lock.synchronize { @drafts.delete(user_id) }
      end
    end
  end
end
