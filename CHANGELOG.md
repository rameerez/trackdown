## [0.4.0] - 2026-08-15

Two things arrive together in this release.

**Amazon CloudFront** joins Cloudflare and MaxMind as a first-class provider, so an app behind the AWS CDN gets the same header-based geolocation with no API keys, no database, and no extra gems.

**Every result now explains how it knows what it knows.** A location on its own is a guess you cannot account for later; if you use one for a fraud check, an abuse report, or an audit trail, you also need to know which provider answered, when, how precise that provider says it is, whether you vouched for the request it came from, and — when there is no answer — exactly why. All of that now travels on the result, and none of it is guessed: a field the answering provider cannot supply is `nil`, never a plausible-looking placeholder.

Upgrading is meant to be uneventful. Every existing reader, alias, and provider signature is unchanged, `to_h` still returns the same 13 keys in the same order, and `country_name` and `city` still say `"Unknown"` exactly as before. The one thing to check before upgrading is Ruby: the minimum is now 3.1.

### Provenance: every result now explains how it knows

- Every `LocationResult` reports which provider answered and from where: `provider_name` (`:cloudflare`, `:cloudfront`, `:maxmind` — the same symbols you'd set as `config.provider`), `provider_source` (`:cloudflare_request_headers`, `:cloudfront_request_headers`, `:maxmind_local_database`), and `resolved_at`. `:auto` reports the provider that actually won, after every fallback.
- Add `available?`, `unavailable?`, and `unavailable_reason`, so an unresolved lookup no longer has to be detected by comparing against the display string `"Unknown"`. The reasons are stable and never translated: `:no_provider_available`, `:address_not_found`, `:provider_returned_unknown_country`, `:provider_data_incomplete`.
- Add `estimated?`. It is true whenever a provider returned any inferred location, including a partial city/coordinate result with no country; it is false when nothing spatial was resolved. This is deliberately independent from `available?`, which means a country could be named. GeoIP does not prove a person, household, or device was at the result: https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy
- Add `LocationResult.unavailable(reason, **provenance)` for building an explicitly unresolved result. It requires exactly one reason and rejects a conflicting `unavailable_reason:` hidden in the provenance hash.
- Cloudflare's `T1` (the Tor network) now keeps its country code but reports `:provider_returned_unknown_country` and a white unknown flag instead of a malformed regional-indicator glyph. `XX` and Unicode's `ZZ` unknown territory are unavailable. Cloudflare contract: https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-ipcountry. Unicode `XK`/`ZZ` semantics: https://www.unicode.org/reports/tr35/tr35-78/tr35.html#unicode_region_subtag_validity
- Ignore non-string or malformed Cloudflare optional values and non-string, invalidly encoded, or malformed country values instead of allowing untrusted request data to raise from a lookup. Exact Cloudflare header contract: https://developers.cloudflare.com/fundamentals/reference/http-headers/
- Apply finite WGS-84 latitude/longitude bounds to Cloudflare headers, matching CloudFront. Exact field source: https://developers.cloudflare.com/rules/transform/managed-transforms/reference/#add-visitor-location-headers. Exact bounds: https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2
- Accept a coordinate header only when it spells a plain decimal number. `Kernel#Float` reads `"0x10"` as a perfectly valid latitude of `16.0`, and converting an absurd exponent makes Ruby warn in verbose mode, so both are rejected before any conversion happens. This uses no library beyond Ruby itself: the gem's only runtime dependency is still `countries`.

### MaxMind accuracy and database provenance

- MaxMind results now expose `accuracy_radius_in_kilometers` (aliased `accuracy_radius_km`), previously dropped, together with `accuracy_radius_confidence_percentage`, which MaxMind documents as 67%: https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy
- MaxMind results now identify the exact reader/database generation that answered: `database_build_epoch` and `database_built_at` come from that reader's metadata, and `database_sha256` lazily digests the file generation captured before the reader opened. Pooled readers for the same path, file identity, and build share one fingerprint. An older in-flight lookup can never combine database A's result/build epoch with database B's digest; if its path has been replaced, its digest is honestly `nil`. MaxMind metadata contract: https://maxmind.github.io/MaxMind-DB/#build_epoch. Exact memory-reader source: https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/memory_reader.rb#L7-L15. Exact file-reader source: https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/file_reader.rb#L36-L55
- `to_h` deliberately leaves `database_sha256` out of its default shape, because producing it means reading the whole database file. Ask for it by name — `result.database_sha256`, or `to_h(only: %i[database_sha256])` — so serializing a result can never turn into disk I/O you didn't ask for.
- An address that isn't in the database still reports which database was searched.
- `Trackdown.update_database` now writes and flushes a same-directory temporary file, requires a real `.mmdb` archive entry, replaces the destination with one `File.rename`, and drops the cached pool so the next lookup opens the new database. A failed/malformed archive leaves the working database intact, and an already-open lookup can finish on its old reader. Ruby rename contract: https://docs.ruby-lang.org/en/3.3/File.html#method-c-rename. MaxMind `MODE_FILE` reader source: https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/file_reader.rb#L36-L55
- Cloudflare and CloudFront results return `nil` for every accuracy and database field rather than inventing values.

### Host-verified source trust

- Add `source_trust` (`:host_verified` or `:unverified`) and `source_was_verified_by_host?` (aliased `host_verified?`).
- Add provider-specific `config.verify_request_came_through_trusted_cloudflare_path_with { |request| ... }` and `config.verify_request_came_through_trusted_cloudfront_path_with { |request| ... }`. Only the matching provider's verifier can produce `:host_verified`; a trusted CloudFront path cannot authenticate forwarded `CF-*` headers, and a trusted Cloudflare path cannot authenticate forwarded `CloudFront-*` headers. Cloudflare passes ordinary request headers: https://developers.cloudflare.com/fundamentals/reference/http-headers/#request-headers. CloudFront's managed all-viewer policy forwards every viewer header: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
- Make the documented shared-secret verifier fail closed when either credential is blank. Rails implements `secure_compare` as an equal-length check plus fixed-length comparison, so two empty strings compare equal: https://api.rubyonrails.org/classes/ActiveSupport/SecurityUtils.html#method-c-secure_compare
- Trackdown never infers trust from header presence: matching `CF-Connecting-IP` or `CloudFront-Viewer-Address` to the requested IP is corroboration, not proof that a request reached the origin through that CDN. Origin-protection sources: https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/, https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/#block-other-ip-addresses-recommended, https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html, and https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
- Trackdown reports this trust state; it does not act on it. What an unverified location may be used for stays your application's decision.

### Serializing only what you want to keep

- `to_h` accepts `only:`, `include_country_info:`, and `include_provenance:`. Callers can persist an explicit field allowlist—in the order named—without hand-building a hash or accidentally storing the large derived `country_info` payload. What you name is what you get: unknown fields raise and explicitly named fields are never dropped. `FIELDS` lists every valid name; `LOCATION_FIELDS`, `PROVENANCE_FIELDS`, and `DEFAULT_FIELDS` are ready-made slices.
- The no-argument `to_h` remains API-compatible: the same 13 keys, in the same order, with the same values. `include_provenance: true` opts into every provenance field except the lazy database digest. This satisfies the exact compatibility requirement in issue #8: https://github.com/rameerez/trackdown/issues/8

### Compatibility

- Every new constructor keyword is optional, and providers can build a result without supplying any of them.
- `country_name` and `city` still return the display string `"Unknown"` when a provider has no value. New code should branch on `available?` / `unavailable_reason` and read `country_code`, which is `nil`, instead of parsing display strings.
- No new runtime dependency, service, or network lookup.
- **Ruby 3.1 or newer is now required**, up from 3.0. Ruby 3.0 reached end of life in March 2024 and is no longer tested anywhere. Sources: https://www.ruby-lang.org/en/downloads/branches/
- The published gem now contains only the library and the files you would actually read — `lib/`, `README.md`, `CHANGELOG.md`, `LICENSE.txt`. Development scaffolding (`Rakefile`, `sig/`, `.simplecov`, agent instruction files) is no longer shipped to applications.
- A test now asserts the dependency contract itself: every `require` in `lib/` has to name a declared runtime dependency, a gem that ships with the running Ruby, or something guarded by `rescue LoadError`. Ruby keeps moving former standard-library gems out of the default set — `bigdecimal` in 3.4 — and a require that works on a developer's machine can still be a `LoadError` in an application. Sources: https://docs.ruby-lang.org/en/3.4/standard_library_md.html

### Amazon CloudFront

- Add an **Amazon CloudFront** provider (`:cloudfront`) that reads country, city, region, timezone, coordinates, postal code, and metro code from `CloudFront-Viewer-*` request headers without adding runtime dependencies. Exact AWS header contract: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
- Preserve CloudFront `XK` as Kosovo even though it is outside the `countries` gem's assigned ISO catalog; continue rejecting `ZZ` as unknown/invalid. Exact Unicode CLDR semantics: https://www.unicode.org/reports/tr35/tr35-78/tr35.html#unicode_region_subtag_validity
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
