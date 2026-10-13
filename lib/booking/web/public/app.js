// What works the same inside Telegram and out of it.
(function () {
  document.documentElement.classList.add("js");

  // The City picker is a <details>, which only closes from its own pill. A
  // tap anywhere else, or Escape, closes it as a menu would.
  var closePickers = function (except) {
    Array.prototype.forEach.call(document.querySelectorAll("details.city-picker[open]"), function (picker) {
      if (picker !== except) picker.open = false;
    });
  };
  document.addEventListener("click", function (event) { closePickers(event.target.closest("details.city-picker")); });
  document.addEventListener("keydown", function (event) { if (event.key === "Escape") closePickers(null); });

  // The Share screen's span pickers: a change is the request, so a second
  // tap on "Show" is not asked for. The button stays for a page without JS.
  document.addEventListener("change", function (event) {
    var form = event.target.closest("form[data-autosubmit]");
    if (form) form.submit();
  });

  // The button that shares the ticked hours as a Game. Nothing ticked, it
  // says how to start and cannot be pressed; something ticked, it names the
  // stretch it will share. Without JS it is always pressable, and an empty
  // press lands back on the hours.
  var pick = document.querySelector("[data-game-pick]");
  if (pick) {
    var label = pick.querySelector("span") || pick;
    var ready = label.textContent;
    var boxes = document.querySelectorAll('input[form="' + pick.form.id + '"]');
    // Hours count from the page's own midnight, so 25 is 01:00 the next day.
    var clock = function (hour) { return ("0" + (hour % 24)).slice(-2) + ":00"; };
    var sync = function () {
      var hours = Array.prototype.filter.call(boxes, function (box) { return box.checked; })
        .map(function (box) { return Number(box.value); });
      var ticked = hours.length > 0;
      pick.disabled = !ticked;
      label.textContent = ticked
        ? ready + " · " + clock(Math.min.apply(null, hours)) + "–" + clock(Math.max.apply(null, hours) + 1)
        : pick.getAttribute("data-none");
      pick.form.classList.toggle("is-armed", ticked);
    };
    Array.prototype.forEach.call(boxes, function (box) { box.addEventListener("change", sync); });
    // A back button can restore ticks the page did not draw.
    window.addEventListener("pageshow", sync);
    sync();
  }

  // The Watch form's shortcuts: tick the five weekdays, or the two days of
  // the weekend, in one tap. The boxes stay the truth; these only set them.
  document.addEventListener("click", function (event) {
    var preset = event.target.closest("[data-days]");
    if (!preset) return;

    var days = preset.getAttribute("data-days").split(",");
    document.querySelectorAll('input[name="weekdays[]"]').forEach(function (box) {
      box.checked = days.indexOf(box.value) >= 0;
    });
  });

  // The Watch form's City segment. Every city's clubs are on the page; this
  // shows the picked city's and hides the rest, and unticks whatever is
  // ticked in them, so a watch keeps to one city and nothing hidden goes up
  // with the form. The legend names the city and counts its ticks.
  var watchForm = document.querySelector("[data-watch-form]");
  if (watchForm) {
    var groups = watchForm.querySelectorAll(".club-group[data-city]");
    var cityName = watchForm.querySelector("[data-city-name]");
    var picked = watchForm.querySelector("[data-picked]");
    var chosen = function () {
      var radio = watchForm.querySelector("[data-city-pick]:checked");
      return radio ? radio.value : null;
    };
    var count = function () {
      if (picked) picked.textContent = watchForm.querySelectorAll('input[name="club_slugs[]"]:checked').length;
    };
    var show = function () {
      var city = chosen();
      if (city === null) return count();
      groups.forEach(function (group) {
        var here = group.getAttribute("data-city") === city;
        group.hidden = !here;
        if (!here) group.querySelectorAll("input:checked").forEach(function (box) { box.checked = false; });
      });
      if (cityName) cityName.textContent = city;
      count();
    };
    watchForm.addEventListener("change", function (event) {
      if (event.target.matches("[data-city-pick]")) show();
      else if (event.target.name === "club_slugs[]") count();
    });
    // A back button can restore a segment and ticks the page did not draw.
    window.addEventListener("pageshow", show);
    show();
  }

  // The directory's search: narrows the list as it is typed, by name or
  // area, without a round trip. The rows carry what they are matched on.
  var search = document.querySelector("[data-club-search]");
  if (search) {
    var rows = document.querySelectorAll("[data-club-match]");
    search.addEventListener("input", function () {
      var query = search.value.trim().toLowerCase();
      rows.forEach(function (row) {
        row.hidden = query !== "" && row.getAttribute("data-club-match").indexOf(query) < 0;
      });
    });
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

  // Telegram's own chrome above and below the page takes the page's ground,
  // so the app does not sit in a frame of somebody else's colour. Follows
  // the client when it switches between light and dark.
  var paint = function () {
    document.documentElement.setAttribute("data-theme", tg.colorScheme);
    var ground = getComputedStyle(document.documentElement).getPropertyValue("--ground").trim();
    if (!ground) return;
    try {
      tg.setHeaderColor(ground);
      tg.setBackgroundColor(ground);
      if (tg.setBottomBarColor) tg.setBottomBarColor(ground);
    } catch (e) { /* an older client without these */ }
  };
  if (tg.initData) {
    paint();
    tg.onEvent("themeChanged", paint);
  }

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
