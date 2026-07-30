// Everything Telegram-specific that the server cannot know.
(function () {
  var tg = window.Telegram && Telegram.WebApp;
  if (!tg) return;

  tg.ready();
  tg.expand();

  // A club's booking page has to leave the mini app. Opened as an ordinary
  // link it would load inside this webview, stranding the person on somebody
  // else's checkout with no way back.
  document.addEventListener("click", function (event) {
    var link = event.target.closest("a[data-external]");
    if (!link) return;

    event.preventDefault();
    tg.openLink(link.href);
  });

  // A t.me link needs Telegram's own opener rather than the generic one:
  // openLink would send iOS out to the system browser, where a `?start=…`
  // payload is silently dropped between Safari and the client. openTelegramLink
  // hands the URL to the Telegram UI, which honours the payload as if it were
  // tapped from anywhere else in the app.
  //
  // close() is called explicitly because openTelegramLink to a chat with the
  // *same* bot the mini app belongs to does not dismiss the app on iOS or
  // Android — the desktop client does it for us, but the two mobile ones
  // leave the mini app open over the chat that is trying to answer the tap.
  document.addEventListener("click", function (event) {
    var link = event.target.closest("a[data-tg-link]");
    if (!link) return;

    event.preventDefault();
    tg.openTelegramLink(link.href);
    tg.close();
  });
})();
