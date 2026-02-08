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
