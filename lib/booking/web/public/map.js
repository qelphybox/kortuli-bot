// The maps: the City's clubs on the Clubs screen, and one club's pin on its
// Profile. MapLibre draws the streets from OpenFreeMap's tiles, in a style
// built here from the --map-* tokens in app.css, so it changes theme with the
// page. The pins and cards are the server's HTML; this only places them.
(function () {
  var gl = window.maplibregl;
  if (!gl) return;

  var root = document.documentElement;
  var TILES = "https://tiles.openfreemap.org/planet";
  var GLYPHS = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf";
  // Noto Sans is the only family the tiles' glyph server has. Barlow stays
  // for everything drawn over the map.
  var REGULAR = ["Noto Sans Regular"];
  var BOLD = ["Noto Sans Bold"];
  var ITALIC = ["Noto Sans Italic"];
  // Latin first, for people who do not read Mkhedruli; the local name when
  // the data has nothing else.
  var NAME = ["coalesce", ["get", "name:en"], ["get", "name_int"], ["get", "name"]];
  var LINE = ["==", ["geometry-type"], "LineString"];
  var POINT = ["==", ["geometry-type"], "Point"];

  var classIn = function (classes) { return ["match", ["get", "class"], classes, true, false]; };
  var widths = function (stops) { return ["interpolate", ["exponential", 1.5], ["zoom"]].concat(stops); };

  // The style, with only the layers the spec names: ground, water, green,
  // buildings, roads, and three kinds of label. Points of interest, house
  // numbers, airports and peaks are left out rather than hidden, so nothing
  // argues with the pins.
  var style = function () {
    var css = getComputedStyle(root);
    var c = function (name) { return css.getPropertyValue("--map-" + name).trim(); };
    var label = function (extra) {
      return Object.assign({ "text-color": c("label"), "text-halo-color": c("label-halo"), "text-halo-width": 1.5 }, extra);
    };

    return {
      version: 8,
      glyphs: GLYPHS,
      sources: { omt: { type: "vector", url: TILES } },
      layers: [
        { id: "land", type: "background", paint: { "background-color": c("land") } },
        { id: "park", type: "fill", source: "omt", "source-layer": "park", paint: { "fill-color": c("park") } },
        {
          id: "green", type: "fill", source: "omt", "source-layer": "landcover",
          filter: classIn(["grass", "wood"]), paint: { "fill-color": c("park") }
        },
        { id: "water", type: "fill", source: "omt", "source-layer": "water", paint: { "fill-color": c("water") } },
        {
          id: "waterway", type: "line", source: "omt", "source-layer": "waterway",
          paint: { "line-color": c("water"), "line-width": widths([10, 0.5, 14, 2]) }
        },
        {
          id: "building", type: "fill", source: "omt", "source-layer": "building", minzoom: 13,
          paint: { "fill-color": c("building") }
        },
        {
          id: "path", type: "line", source: "omt", "source-layer": "transportation", minzoom: 13,
          filter: ["all", LINE, classIn(["path", "track"])],
          layout: { "line-cap": "round" },
          paint: { "line-color": c("road"), "line-width": widths([13, 0.5, 14, 1.2]) }
        },
        {
          id: "road-minor", type: "line", source: "omt", "source-layer": "transportation",
          filter: ["all", LINE, classIn(["tertiary", "minor", "service"])],
          layout: { "line-cap": "round", "line-join": "round" },
          paint: { "line-color": c("road"), "line-width": widths([11, 0.5, 14, 3]) }
        },
        {
          id: "road-casing", type: "line", source: "omt", "source-layer": "transportation",
          filter: ["all", LINE, classIn(["motorway", "trunk", "primary", "secondary"])],
          layout: { "line-cap": "round", "line-join": "round" },
          paint: { "line-color": c("road-casing"), "line-width": widths([10, 4.5, 14, 9]) }
        },
        {
          id: "road-major", type: "line", source: "omt", "source-layer": "transportation",
          filter: ["all", LINE, classIn(["motorway", "trunk", "primary", "secondary"])],
          layout: { "line-cap": "round", "line-join": "round" },
          paint: { "line-color": c("road-major"), "line-width": widths([10, 1.5, 14, 6]) }
        },
        {
          id: "water-name-line", type: "symbol", source: "omt", "source-layer": "water_name",
          filter: LINE,
          layout: { "symbol-placement": "line", "text-field": NAME, "text-font": ITALIC, "text-size": 10 },
          paint: label({})
        },
        {
          id: "water-name", type: "symbol", source: "omt", "source-layer": "water_name",
          filter: POINT,
          layout: { "text-field": NAME, "text-font": ITALIC, "text-size": 10, "text-max-width": 8 },
          paint: label({})
        },
        {
          id: "street-name", type: "symbol", source: "omt", "source-layer": "transportation_name", minzoom: 13,
          layout: { "symbol-placement": "line", "text-field": NAME, "text-font": REGULAR, "text-size": 11 },
          paint: label({})
        },
        {
          id: "district", type: "symbol", source: "omt", "source-layer": "place", minzoom: 10.5,
          filter: classIn(["suburb", "quarter", "neighbourhood"]),
          layout: {
            "text-field": NAME, "text-font": BOLD, "text-size": 10, "text-transform": "uppercase",
            "text-letter-spacing": 0.12, "text-max-width": 8
          },
          paint: label({})
        }
      ]
    };
  };

  // A map on `container`, still or not, that redraws in the other theme
  // when the page switches. No map at all where WebGL is refused — the page
  // keeps whatever it drew before this ran.
  var draw = function (container, options) {
    var map;
    try {
      map = new gl.Map(Object.assign({
        container: container,
        style: style(),
        attributionControl: false,
        minZoom: 10,
        maxZoom: 14,
        // Flat and north up: a city map to find a club on, nothing to tilt.
        maxPitch: 0,
        dragRotate: false,
        pitchWithRotate: false,
        touchPitch: false
      }, options));
    } catch (e) {
      return null;
    }
    map.touchZoomRotate.disableRotation();
    map.keyboard.disableRotation();

    var restyle = function () { map.setStyle(style()); };
    new MutationObserver(restyle).observe(root, { attributes: true, attributeFilter: ["data-theme"] });
    var scheme = window.matchMedia && matchMedia("(prefers-color-scheme: dark)");
    if (scheme && scheme.addEventListener) scheme.addEventListener("change", restyle);

    return map;
  };

  var lngLat = function (el) { return [Number(el.getAttribute("data-lng")), Number(el.getAttribute("data-lat"))]; };

  // --- A club's Profile: its pin on a still map, under the link ----------
  var preview = document.querySelector("[data-map-preview]");
  if (preview) {
    var still = draw(preview, { center: lngLat(preview), zoom: 14, interactive: false });
    if (still) {
      still.once("load", function () {
        preview.classList.add("is-drawn");
        preview.querySelectorAll(".place__pin-mark, .place__credit").forEach(function (el) { el.hidden = false; });
      });
    }
  }

  // --- The Clubs screen's map ---------------------------------------------
  var screen = document.querySelector("[data-clubs-map]");
  if (!screen) return;

  var pins = Array.prototype.slice.call(screen.querySelectorAll("[data-pin]"));
  var hint = screen.querySelector("[data-map-hint]");
  var said = hint && hint.textContent;

  // Every pin in view, under the chips and over the hint; with none, the
  // City's centre. Panning stops a little past the clubs, so the map cannot
  // be lost somewhere with nothing on it.
  var area = new gl.LngLatBounds();
  pins.forEach(function (pin) { area.extend(lngLat(pin)); });
  var centre = (screen.getAttribute("data-centre") || "41.7151,44.8271").split(",").map(Number);
  if (area.isEmpty()) area.extend([centre[1], centre[0]]);
  var view = new gl.LngLatBounds(area.getSouthWest(), area.getNorthEast());
  var sw = area.getSouthWest();
  var ne = area.getNorthEast();
  var padLng = Math.max((ne.lng - sw.lng) * 0.1, 0.06);
  var padLat = Math.max((ne.lat - sw.lat) * 0.1, 0.045);

  var map = draw(screen.querySelector("[data-map-canvas]"), {
    bounds: view,
    fitBoundsOptions: { padding: { top: 76, bottom: 72, left: 36, right: 36 }, maxZoom: 13 },
    maxBounds: [[sw.lng - padLng, sw.lat - padLat], [ne.lng + padLng, ne.lat + padLat]]
  });
  if (!map) {
    if (hint) hint.textContent = "This device cannot draw the map — try the list";
    return;
  }

  // The map takes the whole screen's swipes; Telegram's own swipe-down to
  // close would otherwise win half of them.
  var tg = window.Telegram && Telegram.WebApp;
  if (tg && tg.initData && tg.isVersionAtLeast && tg.isVersionAtLeast("7.7")) tg.disableVerticalSwipes();

  var say = function (text) {
    if (!hint) return;
    hint.textContent = text;
  };

  // --- Pins and the card of the one tapped -------------------------------
  var LAYER = { free: 3, taken: 2, unknown: 2, shut: 1 };
  var depth = function (pin) {
    var state = pin.className.match(/pin--(\w+)/);
    return pin.getAttribute("aria-pressed") === "true" ? 10 : LAYER[state && state[1]] || 1;
  };

  var picked = null;
  var pick = function (slug) {
    picked = slug;
    pins.forEach(function (pin) {
      pin.setAttribute("aria-pressed", String(pin.getAttribute("data-pin") === slug));
      pin.style.zIndex = depth(pin);
    });
    var card = null;
    screen.querySelectorAll("[data-card]").forEach(function (each) {
      each.hidden = each.getAttribute("data-card") !== slug;
      if (!each.hidden) card = each;
    });
    if (hint) hint.hidden = !!card;
    if (!card) return;

    // The pin lands in the middle of what the card leaves showing.
    var pin = pins.filter(function (each) { return each.getAttribute("data-pin") === slug; })[0];
    map.easeTo({ center: lngLat(pin), offset: [0, -card.offsetHeight / 2 + 24], duration: 400 });
  };
  var unpick = function () {
    if (picked === null) return;
    picked = null;
    pins.forEach(function (pin) {
      pin.setAttribute("aria-pressed", "false");
      pin.style.zIndex = depth(pin);
    });
    screen.querySelectorAll("[data-card]").forEach(function (each) { each.hidden = true; });
    if (hint) hint.hidden = false;
  };

  pins.forEach(function (pin) {
    pin.style.zIndex = depth(pin);
    pin.addEventListener("click", function () { pick(pin.getAttribute("data-pin")); });
    new gl.Marker({ element: pin, anchor: "bottom" }).setLngLat(lngLat(pin)).addTo(map);
  });

  // A tap on the map itself, anywhere but a pin, puts the card away.
  map.on("click", function (event) {
    if (event.originalEvent.target.closest(".pin")) return;
    unpick();
  });
  screen.addEventListener("click", function (event) {
    if (event.target.closest("[data-card-close]")) unpick();
  });

  // --- The credit, folded to an "i" until asked for ----------------------
  var credit = screen.querySelector("[data-map-attr]");
  if (credit) {
    credit.addEventListener("click", function () {
      var open = credit.getAttribute("aria-expanded") !== "true";
      credit.setAttribute("aria-expanded", String(open));
      credit.nextElementSibling.hidden = !open;
    });
  }

  // --- "Where am I" --------------------------------------------------------
  // Only asks when tapped. The dot stays on the page: the coordinates go
  // nowhere. Telegram's own LocationManager where the client has one, as the
  // City picker does; the browser's otherwise.
  var locate = screen.querySelector("[data-map-locate]");
  if (!locate) return;

  var me = null;
  var busy = function (on) {
    if (on) locate.setAttribute("aria-busy", "true");
    else locate.removeAttribute("aria-busy");
  };
  var found = function (lat, lng) {
    busy(false);
    if (!me) {
      var dot = document.createElement("span");
      dot.className = "map-me";
      dot.setAttribute("aria-hidden", "true");
      me = new gl.Marker({ element: dot }).setLngLat([lng, lat]).addTo(map);
    } else {
      me.setLngLat([lng, lat]);
    }
    var bounds = map.getMaxBounds();
    if (bounds && !bounds.contains([lng, lat])) {
      unpick();
      return say("You are outside the map of these clubs");
    }
    map.easeTo({ center: [lng, lat], zoom: Math.max(map.getZoom(), 13), duration: 600 });
  };
  var failed = function (text) {
    busy(false);
    unpick();
    say(text);
    setTimeout(function () { say(said); }, 4000);
  };

  var manager = tg && tg.initData && tg.isVersionAtLeast && tg.isVersionAtLeast("8.0") ? tg.LocationManager : null;
  var denied = function () { return manager.isAccessRequested && !manager.isAccessGranted; };
  var viaTelegram = function () {
    if (denied()) return manager.openSettings();

    busy(true);
    manager.getLocation(function (where) {
      if (where) return found(where.latitude, where.longitude);
      failed(denied() ? "Location is off — allow it in Telegram" : "Could not find you");
    });
  };
  var viaBrowser = function () {
    busy(true);
    navigator.geolocation.getCurrentPosition(
      function (position) { found(position.coords.latitude, position.coords.longitude); },
      function (error) { failed(error.code === 1 ? "No location, so no dot" : "Could not find you"); },
      { maximumAge: 600000, timeout: 15000 }
    );
  };

  var ask = null;
  var offer = function (how) {
    ask = how;
    locate.hidden = false;
  };
  locate.addEventListener("click", function () { if (ask) ask(); });

  var ready = function () {
    if (manager.isLocationAvailable) offer(viaTelegram);
    else if (navigator.geolocation) offer(viaBrowser);
  };
  if (manager) {
    // The City picker on the same page may have started it already.
    if (manager.isInited) ready();
    else manager.init(ready);
  } else if (navigator.geolocation) {
    offer(viaBrowser);
  }
})();
