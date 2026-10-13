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

// The City picker. The pill is a link to the picker's own page and the cards
// are radios in one form, so everything here only adds: the sheet, a button
// that names the ticked city, and "Use my location".
(function () {
  var sheet = document.getElementById("city-sheet");

  // The pill opens the picker already drawn into the page, over the screen,
  // rather than going to its page — unless the webview is too old for a
  // modal <dialog>, when the link still does.
  document.addEventListener("click", function (event) {
    var pill = event.target.closest("[data-city-sheet]");
    if (!pill || !sheet || typeof sheet.showModal !== "function") return;

    event.preventDefault();
    sheet.showModal();
  });

  // The × and the backdrop close it, Escape on its own. The picker fills the
  // dialog, so a tap that lands on the dialog itself was on the backdrop.
  if (sheet) {
    sheet.addEventListener("click", function (event) {
      if (event.target !== sheet && !event.target.closest("[data-city-close]")) return;

      event.preventDefault();
      sheet.close();
    });
  }

  var picker = document.querySelector("[data-city-picker]");
  if (!picker) return;

  var go = picker.querySelector("[data-city-go]");
  var hint = picker.querySelector("[data-city-hint]");
  var idle = hint.textContent;
  var say = function (text) { hint.textContent = text; };
  var sync = function () {
    var ticked = picker.querySelector('input[name="city"]:checked');
    if (ticked && go) go.textContent = ticked.value;
  };
  picker.addEventListener("change", sync);
  // A back button can restore a tick the page did not draw.
  window.addEventListener("pageshow", sync);

  // Closed without confirming: nothing was picked, so the next open starts
  // from the city on the screen again.
  if (sheet) {
    sheet.addEventListener("close", function () {
      picker.reset();
      sync();
      say(idle);
    });
  }

  // "Use my location". Only asks when tapped, and only says where the person
  // looks to be: the nearest centre the cards carry is worked out here, the
  // coordinates go nowhere, and the button underneath still confirms.
  var locate = picker.querySelector("[data-city-locate]");
  var cards = picker.querySelectorAll("[data-lat]");
  if (!locate || cards.length === 0) return;

  // Further than this from every city, it is the nearest, not "where you are".
  var NEAR_KM = 50;
  var km = function (lat1, lng1, lat2, lng2) {
    var rad = Math.PI / 180;
    var a = Math.pow(Math.sin((lat2 - lat1) * rad / 2), 2) +
      Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.pow(Math.sin((lng2 - lng1) * rad / 2), 2);
    return 12742 * Math.asin(Math.sqrt(a));
  };
  var done = function () { locate.removeAttribute("aria-busy"); };
  var found = function (lat, lng) {
    done();
    var nearest = null;
    var best = Infinity;
    Array.prototype.forEach.call(cards, function (card) {
      var distance = km(lat, lng, Number(card.getAttribute("data-lat")), Number(card.getAttribute("data-lng")));
      if (distance < best) { best = distance; nearest = card; }
    });
    nearest.querySelector('input[name="city"]').checked = true;
    sync();
    var city = nearest.getAttribute("data-city");
    say(best <= NEAR_KM ? "You look to be in " + city : "Nearest with courts: " + city);
  };
  var refused = function () { done(); say("No location, so pick your city below"); };
  var lost = function () { done(); say("Could not find you, so pick your city below"); };
  var seeking = function () { locate.setAttribute("aria-busy", "true"); say("Finding you…"); };

  // Telegram's own LocationManager (Bot API 8.0) asks once per bot and
  // remembers the answer. Once refused, asking again does nothing, so a tap
  // opens the settings where it can be allowed instead — only ever from a tap.
  var tg = window.Telegram && Telegram.WebApp;
  var manager = tg && tg.initData && tg.isVersionAtLeast && tg.isVersionAtLeast("8.0") ? tg.LocationManager : null;
  var OFF = "Location is off. Tap to allow it in Telegram";
  var denied = function () { return manager.isAccessRequested && !manager.isAccessGranted; };
  var viaTelegram = function () {
    if (denied()) return manager.openSettings();

    seeking();
    manager.getLocation(function (where) {
      if (where) return found(where.latitude, where.longitude);
      if (!denied()) return refused();

      done();
      say(OFF);
    });
  };
  var viaBrowser = function () {
    seeking();
    navigator.geolocation.getCurrentPosition(
      function (position) { found(position.coords.latitude, position.coords.longitude); },
      function (error) { error.code === 1 ? refused() : lost(); },
      { maximumAge: 600000, timeout: 15000 }
    );
  };

  var ask = null;
  var offer = function (how) {
    ask = how;
    locate.hidden = false;
  };
  locate.addEventListener("click", function () { if (ask) ask(); });

  if (manager) {
    manager.init(function () {
      if (manager.isLocationAvailable) {
        offer(viaTelegram);
        if (denied()) say(OFF);
      } else if (navigator.geolocation) {
        offer(viaBrowser);
      }
    });
  } else if (navigator.geolocation) {
    offer(viaBrowser);
  }
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
