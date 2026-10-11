// What works the same inside Telegram and out of it.
(function () {
  document.documentElement.classList.add("js");

  // The Share screen's span pickers: a change is the request, so a second
  // tap on "Show" is not asked for. The button stays for a page without JS.
  document.addEventListener("change", function (event) {
    var form = event.target.closest("form[data-autosubmit]");
    if (form) form.submit();
  });

  // The button that shares the ticked hours as a Game. Nothing ticked, it
  // says how to start and cannot be pressed; something ticked, it can, and it
  // stays in reach while the list scrolls. Without JS it is always pressable,
  // and an empty press lands back on the hours.
  var pick = document.querySelector("[data-game-pick]");
  if (pick) {
    var ready = pick.textContent;
    var boxes = document.querySelectorAll('input[form="' + pick.form.id + '"]');
    var sync = function () {
      var ticked = Array.prototype.some.call(boxes, function (box) { return box.checked; });
      pick.disabled = !ticked;
      pick.textContent = ticked ? ready : pick.getAttribute("data-none");
      pick.form.classList.toggle("is-armed", ticked);
    };
    Array.prototype.forEach.call(boxes, function (box) { box.addEventListener("change", sync); });
    // A back button can restore ticks the page did not draw.
    window.addEventListener("pageshow", sync);
    sync();
  }

  // Copies the text of the element a button names. The clipboard API wants a
  // secure context and a gesture, and some webviews still refuse it — then the
  // text is selected instead, so a long-press copy is one step away.
  document.addEventListener("click", function (event) {
    var button = event.target.closest("[data-copy]");
    if (!button) return;

    var source = document.querySelector(button.getAttribute("data-copy"));
    if (!source) return;

    var done = function () {
      var label = button.textContent;
      button.textContent = button.getAttribute("data-copied") || label;
      setTimeout(function () { button.textContent = label; }, 1600);
    };
    var select = function () {
      var range = document.createRange();
      range.selectNodeContents(source);
      var selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    };

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(source.textContent).then(done, select);
    } else {
      select();
    }
  });
})();

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

  // The share sheet goes through the same opener, for the same reason — but
  // the app stays open: once the message is sent, the person is likely to
  // want the next day, or a different span, for a different chat.
  document.addEventListener("click", function (event) {
    var link = event.target.closest("a[data-tg-share]");
    if (!link) return;

    event.preventDefault();
    tg.openTelegramLink(link.href);
  });
})();
