## [Unreleased]

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
