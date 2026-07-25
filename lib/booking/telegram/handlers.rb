module Booking
  module Telegram
    # Decides what the bot should say. Deliberately returns Replies instead of
    # calling the API: the whole conversation is then exercisable without a
    # network, a token, or a stub of Telegram's client.
    class Handlers
      Reply = Data.define(:kind, :text, :keyboard, :message_id)

      def self.send_message(text, keyboard: nil) = Reply.new(kind: :send, text:, keyboard:, message_id: nil)
      def self.edit(message_id, text, keyboard: nil) = Reply.new(kind: :edit, text:, keyboard:, message_id:)
      def self.alert(text) = Reply.new(kind: :alert, text:, keyboard: nil, message_id: nil)

      NOTHING = [].freeze

      # Owns the buttons under a watch in /list, the way Wizard owns its own.
      PREFIX = "l".freeze

      def initialize(repos:, drafts: Wizard::Store.new, owner_id: Config.owner_id)
        @repos = repos
        @drafts = drafts
        @owner_id = owner_id
      end

      def on_message(user_id:, text:)
        return [self.class.send_message(Messages.not_for_you)] unless allowed?(user_id)

        case command(text)
        when "/start" then [self.class.send_message(Messages.welcome)]
        when "/help" then [self.class.send_message(Messages.help)]
        when "/watch" then start_wizard(user_id)
        when "/list" then list_watches(user_id)
        else [self.class.send_message(Messages.help)]
        end
      end

      def on_callback(user_id:, data:, message_id:)
        return [self.class.alert(Messages.not_for_you)] unless allowed?(user_id)

        callback = Callback.parse(data)

        case callback.prefix
        when Wizard::PREFIX then advance_wizard(user_id, callback, message_id)
        when PREFIX then manage_watch(user_id, callback, message_id)
        else NOTHING
        end
      end

      private

      # A single-user experiment: with no owner set the bot is open, which is
      # only sensible while the token is not public.
      def allowed?(user_id) = @owner_id.nil? || user_id == @owner_id

      # "/watch@some_bot extra words" -> "/watch"
      def command(text) = text.to_s.strip.split(/\s+/).first.to_s.split("@").first

      def clubs = @repos.clubs.enabled

      def club_names = clubs.to_h { [_1.slug, _1.name] }

      def start_wizard(user_id)
        return [self.class.send_message(Messages.no_clubs_configured)] if clubs.empty?

        draft = Wizard.begin
        @drafts.put(user_id, draft)
        view = Wizard.view(draft, clubs:)
        [self.class.send_message(view.text, keyboard: view.keyboard)]
      end

      def advance_wizard(user_id, callback, message_id)
        draft = @drafts.fetch(user_id)
        # Drafts do not survive a restart, and a stale keyboard is still on the
        # user's screen after one.
        return [self.class.alert(Messages.wizard_expired)] if draft.nil?

        outcome = Wizard.apply(draft, callback, clubs:)

        case outcome.status
        when :ignored then NOTHING
        when :cancelled then cancel_wizard(user_id, message_id)
        when :finished then finish_wizard(user_id, outcome.draft, message_id)
        else redraw_wizard(user_id, outcome, message_id)
        end
      end

      def cancel_wizard(user_id, message_id)
        @drafts.delete(user_id)
        [self.class.edit(message_id, Messages.wizard_cancelled)]
      end

      def redraw_wizard(user_id, outcome, message_id)
        # Nothing moved, so re-sending the identical keyboard would only earn a
        # "message is not modified" from Telegram. The alert is the whole reply.
        return [self.class.alert(outcome.alert)] if outcome.alert

        @drafts.put(user_id, outcome.draft)
        view = Wizard.view(outcome.draft, clubs:)
        [self.class.edit(message_id, view.text, keyboard: view.keyboard)]
      end

      def finish_wizard(user_id, draft, message_id)
        @drafts.delete(user_id)
        watch = @repos.watches.create(
          user_id:,
          club_slugs: draft.club_slugs,
          weekdays: draft.weekdays,
          from_minute: draft.from_minute,
          to_minute: draft.to_minute
        )
        [self.class.edit(message_id, Messages.watch_created(watch, club_names))]
      end

      def list_watches(user_id)
        watches = @repos.watches.for_user(user_id)
        return [self.class.send_message(Messages.no_watches)] if watches.empty?

        names = club_names
        watches.map { self.class.send_message(Messages.watch_summary(_1, names), keyboard: watch_keyboard(_1)) }
      end

      def watch_keyboard(watch)
        toggle = watch.active? ? button("⏸ Pause", "pause", watch) : button("▶️ Resume", "resume", watch)
        [[toggle, button("🗑 Delete", "delete", watch)]]
      end

      def button(text, action, watch)
        Wizard::Button.new(text:, data: Callback.build(PREFIX, action, watch.id))
      end

      def manage_watch(user_id, callback, message_id)
        watch = @repos.watches.find(Integer(callback.value, exception: false))
        # Ownership is checked even though the bot is single-user: the id is
        # user-supplied, and "nobody else is using it" is not an access control.
        return NOTHING unless watch && watch.user_id == user_id

        case callback.action
        when "pause" then set_active(watch, false, message_id)
        when "resume" then set_active(watch, true, message_id)
        when "delete" then delete_watch(watch, message_id)
        else NOTHING
        end
      end

      def set_active(watch, active, message_id)
        @repos.watches.set_active(watch.id, active)
        updated = @repos.watches.find(watch.id)
        [self.class.edit(message_id, Messages.watch_summary(updated, club_names), keyboard: watch_keyboard(updated))]
      end

      def delete_watch(watch, message_id)
        @repos.watches.delete(watch.id)
        [self.class.edit(message_id, Messages.watch_deleted)]
      end
    end
  end
end
