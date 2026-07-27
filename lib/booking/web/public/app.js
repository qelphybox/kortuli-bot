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
})();
