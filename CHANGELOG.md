## [Unreleased]

### Provenance: every result now explains how it knows

- Every `LocationResult` reports which provider answered and from where: `provider_name` (`:cloudflare`, `:cloudfront`, `:maxmind` — the same symbols you'd set as `config.provider`), `provider_source` (`:cloudflare_request_headers`, `:cloudfront_request_headers`, `:maxmind_local_database`), and `resolved_at`. `:auto` reports the provider that actually won, after every fallback.
- Add `available?`, `unavailable?`, and `unavailable_reason`, so an unresolved lookup no longer has to be detected by comparing against the display string `"Unknown"`. The reasons are stable and never translated: `:no_provider_available`, `:address_not_found`, `:provider_returned_unknown_country`, `:provider_data_incomplete`.
- Add `estimated?`. It is true for every resolved location, because GeoIP infers where an address is likely to be and never proves where anyone was. MaxMind documents those limits: https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy
- Add `LocationResult.unavailable(reason, **provenance)` for building an explicitly unresolved result.
- Cloudflare's `T1` (the Tor network) now keeps its country code but reports `:provider_returned_unknown_country`, because Tor is precisely a country Cloudflare could not determine. Only Cloudflare's own two pseudo-codes are treated that way — a code we simply haven't heard of, like Kosovo's user-assigned `XK`, is a real answer. Header contract: https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-ipcountry

### MaxMind accuracy and database provenance

- MaxMind results now expose `accuracy_radius_in_kilometers` (aliased `accuracy_radius_km`), previously dropped, together with `accuracy_radius_confidence_percentage`, which MaxMind documents as 67%: https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy
- MaxMind results now identify the database that answered: `database_build_epoch` and `database_built_at` come from the database's own metadata, and `database_sha256` digests the file. The digest is computed the first time something asks for it and then reused for as long as the file stays put — once per database version, per process — so an ordinary lookup costs what it always did. If the file is replaced underneath us the digest becomes `nil` rather than describing a file we are no longer reading, and the build date re-reads from whichever database is now answering.
- `to_h` deliberately leaves `database_sha256` out of its default shape, because producing it means reading the whole database file. Ask for it by name — `result.database_sha256`, or `to_h(only: %i[database_sha256])` — so serializing a result can never turn into disk I/O you didn't ask for.
- An address that isn't in the database still reports which database was searched.
- `Trackdown.update_database` now reopens the database it just downloaded, instead of serving the previous one until the process restarts. `Trackdown::Providers::MaxmindProvider.reset_database!` does the same on demand — useful in web workers when the refresh ran in a separate process. Neither interrupts a lookup already in flight.
- Cloudflare and CloudFront results return `nil` for every accuracy and database field rather than inventing values.

### Host-verified source trust

- Add `source_trust` (`:host_verified` or `:unverified`) and `source_was_verified_by_host?` (aliased `host_verified?`).
- Add `config.verify_request_came_through_trusted_cdn_path_with { |request| ... }`, the only thing that can ever produce `:host_verified`. Trackdown never infers trust from header presence: matching `CF-Connecting-IP` or `CloudFront-Viewer-Address` to the requested IP is useful corroboration, but it is not proof that a request reached the origin through the CDN. Only your own origin protection is: https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/ and https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
- Trackdown reports this trust state; it does not act on it. What an unverified location may be used for stays your application's decision.

### Serializing only what you want to keep

- `to_h` accepts `only:` and `include_country_info:`, so callers can persist an explicit field allowlist — in the order they name it — without hand-building a hash or accidentally storing the large derived `country_info` payload. What you name is what you get: naming a field that doesn't exist raises, and nothing you name is ever dropped. `Trackdown::LocationResult::FIELDS` lists every valid name, and `LOCATION_FIELDS` / `PROVENANCE_FIELDS` are ready-made slices.
- The no-argument `to_h` keeps every key it had, with the same values, and now also carries the provenance fields. Code that persists `result.to_h` verbatim will store more keys than before; pass `only:` to pin an exact shape.

### Compatibility

- Every new constructor keyword is optional, and providers can build a result without supplying any of them.
- `country_name` and `city` still return the display string `"Unknown"` when a provider has no value. New code should branch on `available?` / `unavailable_reason` and read `country_code`, which is `nil`, instead of parsing display strings.
- No new runtime dependency, service, or network lookup.

### Amazon CloudFront

- Add an **Amazon CloudFront** provider (`:cloudfront`) that reads country, city, region, timezone, coordinates, postal code, and metro code from `CloudFront-Viewer-*` request headers without adding runtime dependencies. Exact AWS header contract: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
- Validate CloudFront countries against assigned ISO 3166-1 alpha-2 records, decode AWS's RFC 3986 percent-encoded UTF-8 location values, reject malformed encoding, and reject non-finite or out-of-range WGS-84 coordinates. Encoding source: https://www.rfc-editor.org/rfc/rfc3986#section-2.1. Coordinate source: https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2
- Derive `continent` from the validated country via the existing `countries` dependency and normalize it to the same two-letter code (`NA`, `EU`, …) returned by other providers.
- Make `:auto` require the target IP to match `CF-Connecting-IP` or `CloudFront-Viewer-Address`; missing, malformed, and mismatching corroborators fall through to the next provider. Cloudflare source: https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-connecting-ip. CloudFront source: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
- Make `:auto` fail closed when both CDN candidates match: try MaxMind and otherwise return `Unknown`. AWS documents that `AllViewerAndCloudFrontHeaders-2022-06` forwards every viewer header, so header presence cannot safely resolve that ambiguity: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
- Document the required CloudFront origin trust boundary. AWS recommends requiring a CloudFront-added custom header at custom origins to prevent direct bypass: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html and https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
- Document the equivalent Cloudflare trust boundary and its Authenticated Origin Pulls option: https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/

## [0.3.1] - 2026-02-24

- Fix incorrect Cloudflare geolocation when an upstream proxy sits before Cloudflare
- In `:auto` mode, compare `CF-Connecting-IP` with the target IP and fall back to MaxMind on mismatch
- Normalize compared IPs with `IPAddr` so equivalent IPv6 / IPv4-mapped forms are treated as matches
- Add tests covering matching and mismatching `CF-Connecting-IP` scenarios

## [0.3.0] - 2026-02-08

- Add 8 new geolocation fields: `region`, `region_code`, `continent`, `timezone`, `latitude`, `longitude`, `postal_code`, `metro_code`
- All new fields available from both Cloudflare and MaxMind providers
- All 10 Cloudflare "Add visitor location headers" now fully supported
- Backward compatible — all new fields are optional, existing API unchanged
- `to_h` now includes all new fields

## [0.2.0] - 2026-01-02

- Completely decouple Maxmind from the gem, making it optional
- Add the provider pattern to support more Geo IP providers than MaxMind
- Add support for Cloudflare IP headers out of the box

## [0.1.1] - 2024-10-29

- Fix config validationerror on deployment

## [0.1.0] - 2024-10-29

- Initial release
