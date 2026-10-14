# MapLibre GL JS 5.24.0

The map's renderer, kept here rather than fetched from a CDN: Telegram's SDK
stays the one script the mini app loads from anywhere else. The UMD build,
because it is one plain `<script>` with its worker inlined — no bundler, and
no module workers for an old webview to trip over.

`maplibre-gl.js`, `maplibre-gl.css` and `LICENSE.txt` are `dist/` of the npm
package, unchanged but for the source-map comment. To move to another
version:

```bash
npm pack maplibre-gl@<version> && tar xzf maplibre-gl-<version>.tgz
cp package/dist/{maplibre-gl.js,maplibre-gl.css,LICENSE.txt} lib/booking/web/public/vendor/maplibre/
sed -i '/sourceMappingURL/d' lib/booking/web/public/vendor/maplibre/maplibre-gl.js
```

and change the version above.
