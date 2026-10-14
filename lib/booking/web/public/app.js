// What works the same inside Telegram and out of it.
(function () {
  document.documentElement.classList.add("js");


  // The Share screen's switches and span pickers: a change is the request,
  // so a second tap on "Show" is not asked for. The button stays for a page
  // without JS. A control's own form, not the nearest one around it: the
  // Share screen's switch sits in its bar, apart from the rest.
  document.addEventListener("change", function (event) {
    var form = event.target.form;
    if (form && form.hasAttribute("data-autosubmit")) form.submit();
  });

  // The button that shares the ticked hours as a Game: away until an hour
  // is ticked, then naming the stretch it will share. Without JS it is
  // always there, and an empty press lands back on the hours.
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
      pick.hidden = !ticked;
      if (ticked) label.textContent = ready + " · " + clock(Math.min.apply(null, hours)) + "–" + clock(Math.max.apply(null, hours) + 1);
    };
    Array.prototype.forEach.call(boxes, function (box) { box.addEventListener("change", sync); });
    // A back button can restore ticks the page did not draw.
    window.addEventListener("pageshow", sync);
    sync();
  }

  // A club's Book leaves the app, so it says so on the way out — as a
  // beacon, which never holds the tap up. It counts toward which days
  // people play on.
  document.addEventListener("click", function (event) {
    var book = event.target.closest("[data-book]");
    if (!book || !navigator.sendBeacon) return;

    navigator.sendBeacon("/date/" + book.getAttribute("data-book") + "/booked");
  });

  // A date's strip of hours. Each hour is a link to the same day with it
  // picked or let go, which is all a page without JS needs; with JS the tap
  // asks for that page and swaps in its strip, its list and its links, so
  // the strip keeps its place. The hours picked are read off the strip, not
  // the link, so taps faster than the network stack up rather than undo
  // each other; the last answer to arrive for the last tap wins.
  var hourStrip = document.querySelector("[data-hour-strip]");
  if (hourStrip) {
    // The first hour picked in view, with one before it for context.
    var first = hourStrip.querySelector('[aria-pressed="true"]');
    if (first) hourStrip.scrollLeft = Math.max(0, first.offsetLeft - hourStrip.offsetLeft - 16 - first.offsetWidth);

    var asked = 0;
    var swap = function (html, url, seq) {
      if (seq !== asked) return;
      var next = new DOMParser().parseFromString(html, "text/html");
      document.querySelectorAll("[data-day-swap]").forEach(function (part) {
        var fresh = next.querySelector('[data-day-swap="' + part.getAttribute("data-day-swap") + '"]');
        if (!fresh) return;
        var left = part.scrollLeft;
        part.replaceWith(fresh);
        fresh.scrollLeft = left;
      });
      history.replaceState(null, "", url);
    };

    document.addEventListener("click", function (event) {
      var chip = event.target.closest("[data-hour-strip] [data-hour]");
      if (!chip || !window.fetch || !window.DOMParser) return;

      event.preventDefault();
      chip.setAttribute("aria-pressed", String(chip.getAttribute("aria-pressed") !== "true"));
      var hours = Array.prototype.map.call(
        document.querySelectorAll('[data-hour-strip] [aria-pressed="true"]'),
        function (on) { return on.getAttribute("data-hour"); }
      );
      var url = location.pathname + (hours.length ? "?hours=" + hours.join(",") : "");
      var seq = ++asked;
      fetch(url, { credentials: "same-origin", headers: { "X-Day-Swap": "1" } })
        .then(function (response) { return response.ok ? response.text() : Promise.reject(response); })
        .then(function (html) { swap(html, url, seq); })
        .catch(function () { location.href = url; });
    });
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

  // The map turns Telegram's swipe-down-to-close off so it can have the
  // swipes. The client keeps that across pages but the SDK forgets it — each
  // page starts out believing swipes are on — so every other screen turns
  // them back on, whether or not it is coming from the map.
  if (tg.initData && !document.querySelector("[data-clubs-map]") && tg.isVersionAtLeast && tg.isVersionAtLeast("7.7")) {
    tg.enableVerticalSwipes();
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
