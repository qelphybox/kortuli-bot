// Everything Telegram-specific that the server cannot know. The greeting name
// lives here rather than in the session cookie: it is presentation, and
// keeping it out means the signed cookie carries identity and nothing else.
(function () {
  var tg = window.Telegram && Telegram.WebApp;
  if (!tg) return;

  tg.ready();
  tg.expand();

  var slot = document.getElementById("visitor");
  var user = tg.initDataUnsafe && tg.initDataUnsafe.user;
  if (slot && user && user.first_name) {
    // textContent, never innerHTML — this string comes from a display name.
    slot.textContent = ", " + user.first_name;
  }
})();
