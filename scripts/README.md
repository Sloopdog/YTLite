# Option catalog

`generate_option_catalog.py` builds the app's deterministic option metadata
directly from `yt_dlp.options.create_parser()`. It accepts either the official
platform-independent `yt-dlp` zipapp or a yt-dlp source checkout. The generated
timestamp defaults to the date in yt-dlp's release version so rebuilding the
same input produces byte-for-byte identical JSON.

To refresh from an official stable release, download both assets, verify the
zipapp against the release's official checksum list, and pass that checksum to
the generator as a second check:

```sh
VERSION=2026.07.04
WORK_DIR="/tmp/ytlite-option-catalog-$VERSION"
mkdir -p "$WORK_DIR"
curl -fL -o "$WORK_DIR/SHA2-256SUMS" \
  "https://github.com/yt-dlp/yt-dlp/releases/download/$VERSION/SHA2-256SUMS"
curl -fL -o "$WORK_DIR/yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/download/$VERSION/yt-dlp"
EXPECTED_SHA256="$(awk '$2 == "yt-dlp" { print $1 }' "$WORK_DIR/SHA2-256SUMS")"
test -n "$EXPECTED_SHA256"
test "$(shasum -a 256 "$WORK_DIR/yt-dlp" | awk '{ print $1 }')" = "$EXPECTED_SHA256"
python3 scripts/generate_option_catalog.py \
  --expected-sha256 "$EXPECTED_SHA256" \
  "$WORK_DIR/yt-dlp"
```

Safety values are `normal`, `exec`, `plugin`, `file-url`, `cert-bypass`, and
`password`. Deprecated compatibility switches that yt-dlp still accepts are
kept in a separate group; preset examples appended to formatted help are not
real parser options and are intentionally excluded.
