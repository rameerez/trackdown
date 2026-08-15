# 📍 `trackdown` - Ruby gem to geolocate IPs

[![Gem Version](https://badge.fury.io/rb/trackdown.svg)](https://badge.fury.io/rb/trackdown) [![Build Status](https://github.com/rameerez/trackdown/workflows/Tests/badge.svg)](https://github.com/rameerez/trackdown/actions)

> [!TIP]
> **🚀 Ship your next Rails app 10x faster!** I've built **[RailsFast](https://railsfast.com/?ref=trackdown)**, a production-ready Rails boilerplate template that comes with everything you need to launch a software business in days, not weeks. Go [check it out](https://railsfast.com/?ref=trackdown)!

`trackdown` is a Ruby gem that allows you to geolocate IP addresses easily.

It reads geolocation headers from **Cloudflare** and **Amazon CloudFront** without API calls or additional runtime gems, and it is also a convenient wrapper around **MaxMind**. CDN-side header forwarding and origin protection still need to be configured correctly; the exact requirements are documented below.

`trackdown` offers a clean API for Rails applications to fetch country, city, region, continent, timezone, coordinates, and emoji flag information for any IP address.

Given an IP, it gives you the corresponding:
- 🗺️ Country (two-letter country code + country name)
- 📍 City
- 🏔️ Region / state (e.g. "California") and region code (e.g. "CA")
- 🌍 Continent (e.g. "NA", "EU")
- 🕐 Timezone (e.g. "America/Los_Angeles")
- 📌 Latitude and longitude coordinates
- 📮 Postal code (e.g. "94107")
- 📺 Metro code (e.g. "807")
- 🇺🇸 Emoji flag of the country

And, because a location you can't explain isn't much of a location, every result also tells you [how it knows](#how-do-you-know): which provider answered, when, how precise that provider says it is, whether you vouched for the request it came from, and — when there's no answer — exactly why.

## First, choose your `trackdown` Geo IP provider

### Option 1: Cloudflare (recommended for Cloudflare origins)

If your Rails app is behind Cloudflare, `trackdown` reads the location information Cloudflare adds to origin requests:
- No API keys needed
- No database downloads
- No external dependencies
- Instant lookups from Cloudflare headers

Enable "IP Geolocation" in your Cloudflare dashboard. For the full set of location fields (city, region, coordinates, etc.), enable ["Add visitor location headers"](https://developers.cloudflare.com/rules/transform/managed-transforms/reference/) in Managed Transforms. `:auto` also verifies that the documented [`CF-Connecting-IP` edge-to-origin header](https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-connecting-ip) matches the IP passed to `Trackdown.locate` before trusting the location headers. If Cloudflare's "Remove visitor IP headers" transform suppresses that corroborator, use an explicitly configured provider only after securing the origin.

As with every header-based provider, direct-origin access must be blocked. Cloudflare recommends [blocking traffic that does not come from Cloudflare IPs](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/#block-other-ip-addresses-recommended) or using [Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/) to ensure requests came through its network.

### Option 2: Amazon CloudFront (recommended for CloudFront origins)

If your Rails app is behind Amazon CloudFront, `trackdown` can read CloudFront's viewer-location headers:
- No API keys needed
- No database downloads
- No external dependencies
- Instant lookups from CloudFront `CloudFront-Viewer-*` headers

CloudFront requires explicit distribution and origin configuration:

1. Attach an [origin request policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-origin-requests.html) that adds the viewer-location headers. A custom least-privilege policy containing only the required `CloudFront-*` headers is preferred. AWS's managed [`AllViewerAndCloudFrontHeaders-2022-06` policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront) includes them, but also forwards **every viewer header, cookie, and query string**.
2. Prevent direct access to the origin. Header presence alone does not prove that a request passed through CloudFront. AWS documents how to [add an origin-only custom header](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html) and [configure a custom origin to accept only CloudFront requests](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html).
3. Pass the request and the intended viewer IP: `Trackdown.locate(request.remote_ip, request: request)`.

AWS documents the exact [viewer-location header names, availability rules, address format, and RFC 3986 encoding](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location). `trackdown` validates the country, decodes percent-encoded UTF-8 fields, validates coordinate bounds, and—under `:auto`—requires `CloudFront-Viewer-Address` to match the requested IP.

> [!IMPORTANT]
> If both Cloudflare and CloudFront header families match the target IP, `:auto` fails closed because viewer-forwarded headers make the situation ambiguous. It tries MaxMind and otherwise returns `'Unknown'`. Choose `config.provider = :cloudflare` or `:cloudfront` for an intentional stacked-CDN deployment after securing the origin.

### Option 3: MaxMind (BYOK - Bring Your Own Key)

For apps not behind a supported CDN, offline apps, non-Rails apps, or as a fallback, use MaxMind:
- Requires MaxMind account and license key
- Requires downloading and maintaining a local database
- Works offline once database is downloaded
- Get started at [MaxMind](https://www.maxmind.com/)

### Option 4: Auto

By default, `trackdown` uses **`:auto` mode**. It uses an edge provider only when that provider's documented client-IP header matches the target IP. When no unique edge provider can be verified, it tries MaxMind and otherwise returns `'Unknown'`.

> [!NOTE]
> Trackdown fails gracefully. If no provider is available (no verified CDN headers and no MaxMind database), it returns `'Unknown'` instead of raising an error, so your app doesn't crash due to a missing geolocation provider.


## Installation

`trackdown` needs Ruby 3.1 or newer. Add this line to your application's Gemfile:

```ruby
gem 'trackdown'

# Optional: Only needed if using MaxMind provider
gem 'maxmind-db'        # For MaxMind database access
gem 'connection_pool'   # For connection pooling
```

And then execute:

```bash
bundle install
```

## Setup

### Quick Start (Cloudflare)

If your app is behind Cloudflare, setup is super simple:

1. **Enable IP Geolocation in Cloudflare**

2. **That's it!** No initializer needed. Just use it:

```ruby
# In your controller
Trackdown.locate(request.remote_ip, request: request).country
# => 'United States of America'
```

### Setup with Amazon CloudFront

1. Create an origin request policy that adds these headers:
   - `CloudFront-Viewer-Country`
   - `CloudFront-Viewer-City`
   - `CloudFront-Viewer-Country-Region-Name`
   - `CloudFront-Viewer-Country-Region`
   - `CloudFront-Viewer-Latitude`
   - `CloudFront-Viewer-Longitude`
   - `CloudFront-Viewer-Time-Zone`
   - `CloudFront-Viewer-Postal-Code`
   - `CloudFront-Viewer-Metro-Code`
   - `CloudFront-Viewer-Address` (required for `:auto` IP corroboration)

   AWS source for creating and attaching origin request policies:
   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-origin-requests.html

2. Restrict the custom origin so viewers cannot bypass CloudFront and forge these headers. AWS's documented mechanism is an origin custom header that the origin requires and that CloudFront overwrites before forwarding:
   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html
   https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html

3. Use the request-bound API:

```ruby
Trackdown.locate(request.remote_ip, request: request).country
# => 'United States of America'
```

For a distribution dedicated to this application, use a custom policy containing only the required headers. If you instead use AWS's managed `AllViewerAndCloudFrontHeaders-2022-06` policy, remember that AWS documents it as forwarding all viewer headers, cookies, and query strings:
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront

### Setup with MaxMind

If you want to use `trackdown` with a MaxMind database as the geo IP data provider:

1. **Run the generator**:
```bash
rails generate trackdown:install
```

This will create an initializer file at `config/initializers/trackdown.rb`. Open this file and add your MaxMind license key and account ID next.

2. **Configure your MaxMind credentials** in `config/initializers/trackdown.rb`:
```ruby
Trackdown.configure do |config|
  config.provider = :auto  # or :maxmind to use MaxMind exclusively

  # Use Rails credentials (recommended)
  config.maxmind_account_id = Rails.application.credentials.dig(:maxmind, :account_id)
  config.maxmind_license_key = Rails.application.credentials.dig(:maxmind, :license_key)
end
```

> [!TIP]
> To get your MaxMind account ID and license key, you need to create an account at [MaxMind](https://www.maxmind.com/) and get a license key.

3. **Download the database**:
```ruby
Trackdown.update_database
```

You can configure the path where the MaxMind database will be stored. By default, it will be stored at `db/GeoLite2-City.mmdb`:

```ruby
config.database_path = Rails.root.join('db', 'GeoLite2-City.mmdb').to_s
```

4. **Schedule regular updates** (optional but recommended):

The `trackdown` gem generator creates a `TrackdownDatabaseRefreshJob` job for regularly updating the MaxMind database. You can just get a database the first time and just keep using it, but the information will get outdated and some IPs will become stale or inaccurate.

To keep your IP geolocation accurate, you need to make sure the `TrackdownDatabaseRefreshJob` runs regularly. How you do that, exactly, depends on the queueing system you're using.


If you're using `solid_queue` (the Rails 8 default), you can easily add it to your schedule in the `config/recurring.yml` file like this:

```yaml
production:
  refresh_trackdown_database:
    class: TrackdownDatabaseRefreshJob
    queue: default
    schedule: every Saturday at 4am
```

> [!NOTE]
> MaxMind updates their databases [every Tuesday and Friday](https://dev.maxmind.com/geoip/geoip2/geoip2-update-process/).

## Usage

### With Cloudflare or CloudFront

```ruby
# In your controller - pass the request object
result = Trackdown.locate(request.remote_ip, request: request)
result.country
# => 'United States of America'
```

In `:auto`, `request.remote_ip` must represent the same viewer that the CDN's corroborating IP header represents. If your Rails proxy configuration deliberately produces a different IP, use MaxMind for that target or explicitly select the correctly configured CDN provider.

### With MaxMind or without request object

To geolocate an IP address:

```ruby
# Works anywhere - just needs the IP
result = Trackdown.locate('8.8.8.8')
result.country
# => 'United States'
```

### API Methods

You can do things like:
```ruby
Trackdown.locate('8.8.8.8').emoji
# => '🇺🇸'
```

In fact, there are a few methods you can use:

```ruby
result.country_code    # => 'US'
result.country_name    # => 'United States' (MaxMind's own name for it)
result.country         # => 'United States' (alias for country_name)
result.city            # => 'Mountain View' (from MaxMind or configured CDN headers)
result.region          # => 'California'
result.region_code     # => 'CA'
result.continent       # => 'NA'
result.timezone        # => 'America/Los_Angeles'
result.latitude        # => 37.7749
result.longitude       # => -122.4194
result.postal_code     # => '94107'
result.metro_code      # => '807'
result.flag_emoji      # => '🇺🇸'
result.emoji           # => '🇺🇸' (alias for flag_emoji)
result.country_flag    # => '🇺🇸' (alias for flag_emoji)
result.country_info    # => # Rich country data from the `countries` gem
```

`country_name` comes from MaxMind's own record on the MaxMind path, and from the [`countries` gem](https://github.com/countries/countries) on the Cloudflare and CloudFront paths — so the same country can read `'United States'` or `'United States of America'` depending on who answered. `country_code` is the one to compare against.

And the same result will tell you where all of that came from:

```ruby
result.available?      # => true (did we actually resolve a location?)
result.provider_name   # => :maxmind
result.provider        # => :maxmind (alias for provider_name)
result.resolved_at     # => 2026-08-15 04:22:47 UTC
```

There's [a whole section on that](#how-do-you-know) below.

> [!NOTE]
> The optional fields require Cloudflare's ["Add visitor location headers"](https://developers.cloudflare.com/rules/transform/managed-transforms/reference/), an applicable CloudFront origin request policy, or a MaxMind GeoLite2-City database. AWS notes that city, metro, and postal data may be unavailable and that extended CloudFront location headers are omitted for viewers on AWS networks: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location. Unavailable fields return `nil` (`city` uses `'Unknown'`).

### Rich country information

For `country_info` we're leveraging the [`countries`](https://github.com/countries/countries) gem, so you get a lot of information about the country, like the continent, the region, the languages spoken, the currency, and more:

```ruby
result.country_info.alpha3          # => "USA"
result.country_info.currency_code   # => "USD"
result.country_info.continent       # => 'North America'
result.country_info.nationality     # => 'American'
result.country_info.iso_long_name   # => 'The United States of America'
```

### Hash data

If you prefer a hash, the no-argument form keeps Trackdown's original 13-key
shape exactly:

```ruby
result.to_h
# => {
#      country_code: 'US',
#      country_name: 'United States',
#      city: 'Mountain View',
#      flag_emoji: '🇺🇸',
#      region: 'California',
#      region_code: 'CA',
#      continent: 'NA',
#      timezone: 'America/Los_Angeles',
#      latitude: 37.7749,
#      longitude: -122.4194,
#      postal_code: '94107',
#      metro_code: '807',
#      country_info: { ... }
#    }
```

Ask for provenance when you want the provenance-rich shape:

```ruby
result.to_h(include_provenance: true)
# => {
#      country_code: 'US',
#      country_name: 'United States',
#      city: 'Mountain View',
#      flag_emoji: '🇺🇸',
#      region: 'California',
#      region_code: 'CA',
#      continent: 'NA',
#      timezone: 'America/Los_Angeles',
#      latitude: 37.7749,
#      longitude: -122.4194,
#      postal_code: '94107',
#      metro_code: '807',
#      provider_name: :maxmind,
#      provider_source: :maxmind_local_database,
#      source_trust: nil,
#      resolved_at: 2026-08-15 04:22:47 UTC,
#      available: true,
#      estimated: true,
#      unavailable_reason: nil,
#      accuracy_radius_in_kilometers: 20,
#      accuracy_radius_confidence_percentage: 67,
#      database_build_epoch: 1735689600,
#      database_built_at: 2025-01-01 00:00:00 UTC,
#      country_info: { ... }
#    }
```

Or just the fields you actually want to keep, named in plain English, in the order you name them:

```ruby
result.to_h(only: %i[country_code city latitude longitude accuracy_radius_in_kilometers provider_name])
# => { country_code: 'US', city: 'Mountain View', latitude: 37.7749,
#      longitude: -122.4194, accuracy_radius_in_kilometers: 20, provider_name: :maxmind }
```

`country_info` is a large derived payload, so you can also just leave it out:

```ruby
result.to_h(include_country_info: false)
```

What you name is what you get, in that order — naming a field that doesn't exist raises, and nothing you name is ever dropped, so a typo can't quietly cost you a column in something you're storing.

> [!NOTE]
> The no-argument `to_h` is deliberately backward compatible: same keys, same order, same values. `include_provenance: true` opts into every provenance field except `database_sha256`; a digest can require reading the whole database file, so Trackdown never hides that I/O inside ordinary serialization. Ask for the digest explicitly with `only:` — [see below](#which-database-said-so).

## How do you know?

Geolocating an IP is a guess. A good one, but a guess — and if you're using it for fraud checks, abuse reports, audit trails, or anything you might one day have to explain, the guess is only half of what you need. You also need to know *how it was made*.

So every result carries its own provenance. Nothing here is guessed: every field is either what the provider said, or something derived from it by a rule this README documents. A field the answering provider can't supply is `nil`, never a plausible-looking placeholder.

### Which provider answered, and when

```ruby
result.provider_name    # => :cloudflare, :cloudfront, or :maxmind
result.provider_source  # => :cloudflare_request_headers, :cloudfront_request_headers, or :maxmind_local_database
result.resolved_at      # => 2026-08-15 04:22:47 UTC
result.estimated?       # => true
```

`provider_name` uses the very same symbols you'd set as `config.provider`, so `result.provider_name == :cloudflare` reads exactly like the config that produced it. In `:auto` mode you get the provider that actually won, after every fallback — if Cloudflare was skipped and MaxMind answered, the result says `:maxmind`.

`estimated?` is `true` whenever the provider returned any location estimate. That
includes a partial result with a city or coordinates but no country, even though
that same result is `unavailable?`. It is `false` when nothing spatial was
resolved—for example, a bare Cloudflare `T1` Tor marker. `available?` answers
"could we name a country?"; `estimated?` answers "did the provider return any
inferred location?" Those are intentionally independent questions.

GeoIP never proves that a person or device was at a location. MaxMind explicitly
says its data cannot identify a specific household, individual, or street address
and may locate a VPN or server rather than its end user:
https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy

### Did we actually find anything?

```ruby
result.available?          # => false
result.unavailable?        # => true
result.unavailable_reason  # => :address_not_found
```

The reasons are stable symbols, part of the public API, and never translated:

| Reason | What happened |
|---|---|
| `:no_provider_available` | No usable CDN header result and no MaxMind database. Nobody could answer. |
| `:address_not_found` | We searched a real database and this address simply isn't in it. |
| `:provider_returned_unknown_country` | The CDN answered, but with no country — Cloudflare's `XX`, Unicode's unknown/invalid `ZZ`, or `T1` for a visitor arriving over Tor. |
| `:provider_data_incomplete` | A provider returned a record, but not enough of one to name a country. |

`unavailable?` means precisely *"we could not name a country"*. Some of those results still carry something useful — a Tor result keeps `country_code == 'T1'`, and an incomplete database record can still have a city and coordinates. If those are worth having to you, read them; Trackdown hands back everything it got either way.

> [!NOTE]
> `country_name` and `city` still return the display string `'Unknown'` when a provider has no value, exactly as they always have — existing code keeps working. New code should branch on `available?` / `unavailable_reason` rather than comparing against a display string.

### How precise is it?

MaxMind's City records carry an accuracy radius, and Trackdown passes it straight through:

```ruby
result.accuracy_radius_in_kilometers          # => 20
result.accuracy_radius_km                     # => 20 (alias)
result.accuracy_radius_confidence_percentage  # => 67
```

That reads: *the address is within 20 km of these coordinates, with 67% confidence* — [MaxMind's own definition](https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy). Neither Cloudflare's [exact visitor-location field list](https://developers.cloudflare.com/rules/transform/managed-transforms/reference/#add-visitor-location-headers) nor CloudFront's [exact viewer-location header list](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location) publishes an accuracy figure, so those results return `nil` instead of an invented one.

### Which database said so?

```ruby
result.database_build_epoch  # => 1735689600
result.database_built_at     # => 2025-01-01 00:00:00 UTC
result.database_sha256       # => '4f8b42c22dd3729b519ba6f68d2da7cc…'
```

The build epoch comes from the exact answering reader's database metadata; the
MaxMind DB format defines it as the database build timestamp in Unix-epoch form:
https://maxmind.github.io/MaxMind-DB/#build_epoch. In a serialized hash it is
included only when you ask for provenance or name it with `only:`.

The digest is lazy because it costs a full read of the database file. Trackdown
computes it the first time someone asks and shares that lazy fingerprint among
pooled readers bound to the same path, file identity, and build epoch. Ordinary
lookups and ordinary `to_h` calls never compute it. When you want it, name it:

```ruby
result.database_sha256                       # the reader
result.to_h(only: %i[database_sha256])       # or in a hash
```

Every result retains the fingerprint of the exact reader that answered it. That
matters because the MaxMind Ruby reader can either copy the file into memory when
opened or retain an open file handle, depending on mode:
https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/memory_reader.rb#L7-L15
and
https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/file_reader.rb#L36-L55.
If the configured path is replaced after an older reader opened it, the older
result keeps that reader's build epoch and its digest becomes `nil`; it never
borrows the replacement file's digest. A new reader receives a new fingerprint.

`Trackdown.update_database` writes the complete download to a temporary file in
the destination directory, flushes it, and replaces the configured path with one
`File.rename` only after the archive contains a `.mmdb` file. That prevents
Trackdown's updater from truncating a database underneath a `MODE_FILE` reader.
Ruby's rename contract is documented at
https://docs.ruby-lang.org/en/3.3/File.html#method-c-rename, and the reader's
open-file behavior is visible in the exact source linked above.

> [!NOTE]
> `Trackdown.update_database` drops the cached reader pool in the process that ran it, so that process's next lookup opens the new database. If you refresh from a separate process — a cron job or a `rails runner`, as the scheduling section recommends — your web workers keep serving the database they already have open until they restart. Call `Trackdown::Providers::MaxmindProvider.reset_database!` in a worker to make its next lookup pick up the new file without a restart.

### Did the request really come through your CDN?

Here's the uncomfortable part. `CF-IPCountry` is just a header. Anyone who can reach your origin directly can send you one, and it will look exactly like the real thing. Matching `CF-Connecting-IP` against the IP you're asking about — which `:auto` already does — is useful corroboration, but it is *not* proof that the request came through Cloudflare.

Only your own origin protection can vouch for the request path. Cloudflare and
CloudFront are configured independently: a verified path through one CDN must
never authenticate the other CDN's headers.

For Cloudflare, have the layer that actually validates Authenticated Origin Pulls
or the Cloudflare peer network place a non-viewer-controlled boolean in the Rack
environment, then read that boolean:

```ruby
Trackdown.configure do |config|
  config.verify_request_came_through_trusted_cloudflare_path_with do |request|
    request.env['my_app.cloudflare_origin_was_verified'] == true
  end
end
```

For a CloudFront custom origin header, compare the CloudFront-only secret and
refuse to boot if the expected value is blank:

```ruby
expected_cloudfront_origin_secret =
  Rails.application.credentials.dig(:cloudfront, :origin_secret).to_s
raise 'Missing CloudFront origin secret' if expected_cloudfront_origin_secret.empty?

Trackdown.configure do |config|
  config.verify_request_came_through_trusted_cloudfront_path_with do |request|
    supplied_cloudfront_origin_secret =
      request.env['HTTP_X_CLOUDFRONT_ORIGIN_SECRET'].to_s

    !supplied_cloudfront_origin_secret.empty? &&
      ActiveSupport::SecurityUtils.secure_compare(
        supplied_cloudfront_origin_secret,
        expected_cloudfront_origin_secret
      )
  end
end
```

Both non-empty checks matter. Rails implements `secure_compare` as an equal-byte-
length check followed by a fixed-length comparison, so two empty strings compare
equal:
https://api.rubyonrails.org/classes/ActiveSupport/SecurityUtils.html#method-c-secure_compare

```ruby
result.source_trust                  # => :host_verified (or :unverified)
result.source_was_verified_by_host?  # => true
result.host_verified?                # => true (alias)
```

Without that callback, a request-backed result is always `:unverified` — no matter how complete or how corroborated its headers are. Header presence alone can never produce `:host_verified`. MaxMind results have no request path to verify at all, so their `source_trust` is `nil`.

What you put in each callback is whatever that deployment path actually proves:

- **Cloudflare:** [Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/), or [blocking every IP that isn't Cloudflare's](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/#block-other-ip-addresses-recommended).
- **CloudFront:** [an origin custom header CloudFront adds and viewers can't](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html), plus [restricting the custom origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html).

The separation is security-relevant. Cloudflare documents that it passes ordinary
viewer request headers to the origin:
https://developers.cloudflare.com/fundamentals/reference/http-headers/#request-headers.
AWS documents that `AllViewerAndCloudFrontHeaders-2022-06` forwards all viewer
headers:
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront.
Therefore a trusted CloudFront path cannot vouch for a forwarded `CF-*` family,
and a trusted Cloudflare path cannot vouch for a forwarded `CloudFront-*` family.

> [!IMPORTANT]
> Trackdown **reports** this trust state. It doesn't act on it — an unverified location is still returned in full. Whether an unverified location is good enough to ban an account, or only good enough to show a flag in the UI, is your application's call, not a gem's.

### Putting it together

Act on the strength of the evidence, not just on the answer:

```ruby
location = Trackdown.locate(request.remote_ip, request: request)

if location.available? && location.host_verified?
  enforce_geoblock!(location.country_code)   # evidence you'd be willing to defend
elsif location.available?
  flag_for_review(location.country_code)     # good enough to look at, not to act on
end
```

And when you store it, store how you got it:

```ruby
AbuseReport.create!(
  ip: request.remote_ip,
  **location.to_h(only: %i[
    country_code city latitude longitude accuracy_radius_in_kilometers
    provider_name provider_source source_trust resolved_at database_built_at
  ])
)
```

The names you can pass to `only:` are `Trackdown::LocationResult::FIELDS`. Three
ready-made slices come with it: `LOCATION_FIELDS` (where the IP is),
`PROVENANCE_FIELDS` (how we know), and `DEFAULT_FIELDS` (exactly what a
no-argument `to_h` returns, `country_info` included).

## Configuration

### Provider Options

```ruby
Trackdown.configure do |config|
  # :auto - Use one IP-corroborated edge provider; fall back to MaxMind when none
  #         or both are valid (default, recommended for unambiguous deployments)
  # :cloudflare - Only use Cloudflare headers
  # :cloudfront - Only use Amazon CloudFront headers
  # :maxmind - Only use MaxMind database
  config.provider = :auto
end
```

### Full Configuration Example

```ruby
Trackdown.configure do |config|
  # Provider
  config.provider = :auto

  # MaxMind settings (only needed if using MaxMind)
  config.maxmind_account_id = Rails.application.credentials.dig(:maxmind, :account_id)
  config.maxmind_license_key = Rails.application.credentials.dig(:maxmind, :license_key)
  config.database_path = Rails.root.join('db', 'GeoLite2-City.mmdb').to_s

  # Performance tuning (MaxMind only - requires maxmind-db gem)
  config.timeout = 3
  config.pool_size = 5
  config.pool_timeout = 3
  # config.memory_mode = MaxMind::DB::MODE_MEMORY  # or MODE_FILE to reduce memory

  # General
  config.reject_private_ips = true  # Reject 192.168.x.x, 127.0.0.1, etc.

  # Optional provider-specific source-trust callbacks are documented, with
  # fail-closed examples, in "Did the request really come through your CDN?"
end
```

### Updating the MaxMind database

Only needed when using the MaxMind provider:

```ruby
Trackdown.update_database
```

## How It Works

### Cloudflare Provider

When you enable "IP Geolocation" in Cloudflare, they add the `CF-IPCountry` header to every request. If you also enable ["Add visitor location headers"](https://developers.cloudflare.com/rules/transform/managed-transforms/reference/) (via Managed Transforms), you get all 10 location headers:

| Cloudflare header | `trackdown` field |
|---|---|
| `cf-ipcountry` | `country_code` |
| `cf-ipcity` | `city` |
| `cf-ipcontinent` | `continent` |
| `cf-iplatitude` | `latitude` |
| `cf-iplongitude` | `longitude` |
| `cf-region` | `region` |
| `cf-region-code` | `region_code` |
| `cf-metro-code` | `metro_code` |
| `cf-postal-code` | `postal_code` |
| `cf-timezone` | `timezone` |

Trackdown reads these headers directly from the request—no database lookup or
external API call. It rejects non-finite or out-of-range coordinates using the
same WGS-84 bounds as the CloudFront provider. Exact Cloudflare field source:
https://developers.cloudflare.com/rules/transform/managed-transforms/reference/#add-visitor-location-headers.
Exact coordinate bounds:
https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2.

Cloudflare's `XX` and `T1` values are not countries. Trackdown preserves `T1`
as useful Tor provenance but reports the location unavailable and renders the
white unknown flag rather than a malformed regional-indicator glyph. Unicode's
`ZZ` unknown/invalid territory is unavailable too. Non-string or malformed
optional values, and non-string, invalidly encoded, or malformed country values,
are ignored rather than allowed to raise from a lookup. Exact Cloudflare code contract:
https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-ipcountry.
Exact Unicode `ZZ` semantics:
https://www.unicode.org/reports/tr35/tr35-78/tr35.html#unicode_region_subtag_validity.

### CloudFront Provider

When your app is behind Amazon CloudFront and an origin request policy adds the viewer-location headers, Trackdown maps the following values:

| CloudFront header | `trackdown` field |
|---|---|
| `CloudFront-Viewer-Country` | `country_code` |
| `CloudFront-Viewer-City` | `city` |
| `CloudFront-Viewer-Country-Region-Name` | `region` |
| `CloudFront-Viewer-Country-Region` | `region_code` |
| `CloudFront-Viewer-Latitude` | `latitude` |
| `CloudFront-Viewer-Longitude` | `longitude` |
| `CloudFront-Viewer-Metro-Code` | `metro_code` |
| `CloudFront-Viewer-Postal-Code` | `postal_code` |
| `CloudFront-Viewer-Time-Zone` | `timezone` |

Exact AWS source for every mapped header and its semantics:
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location

Important details from that contract:

- `CloudFront-Viewer-Country` is validated against the `countries` catalog before CloudFront is considered available, with one deliberate exception: `XK` is preserved for Kosovo. Unicode CLDR documents `XK` as established industry practice and `ZZ` as unknown/invalid territory: https://www.unicode.org/reports/tr35/tr35-78/tr35.html#unicode_region_subtag_validity.
- Non-ASCII viewer-location values are RFC 3986 percent-encoded by CloudFront. Trackdown decodes them as UTF-8 without applying HTML form `+`-as-space behavior. RFC source: https://www.rfc-editor.org/rfc/rfc3986#section-2.1.
- Latitude and longitude are accepted only when finite and inside the WGS-84 bounds of `-90..90` and `-180..180`. Bounds source: https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2.
- City, metro code, and postal code may be unavailable. Extended headers are omitted for viewer IPs on the AWS network.
- CloudFront does not provide a continent header, so `continent` is derived from the validated country via the [`countries` gem](https://github.com/countries/countries) and normalized to the same two-letter code (`NA`, `EU`, …) returned by the other providers.

In `:auto`, Trackdown compares the target IP with `CloudFront-Viewer-Address`. A missing, malformed, or mismatching address causes that candidate to be skipped. If Cloudflare and CloudFront both appear valid, Trackdown refuses to guess, tries MaxMind, and otherwise returns `'Unknown'`. An explicitly configured `:cloudfront` provider reads valid CloudFront location headers without requiring the address comparison, which is useful only when the deployment's CloudFront trust boundary has already been secured.

The AWS managed policy includes every header in the table plus `CloudFront-Viewer-Address`, but it also forwards all viewer headers, cookies, and query strings:
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront

Header values are trustworthy only when the origin rejects direct requests. Exact AWS sources:
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html

### MaxMind Provider

Downloads the [GeoLite2-City](https://dev.maxmind.com/geoip/docs/databases/city-and-country/) database to your server and performs local lookups using connection pooling for performance. All fields (`country`, `city`, `region`, `continent`, `timezone`, `latitude`, `longitude`, `postal_code`, `metro_code`) are extracted from the database record, along with the record's [`accuracy_radius`](https://dev.maxmind.com/geoip/docs/databases/city-and-country/city-binary/) and the identity of the database that answered — see [How do you know?](#how-do-you-know).


## Docker & Container Deployments

When deploying with Docker, Kubernetes, or similar container orchestration, the MaxMind database file needs special handling since container filesystems are ephemeral.

### Option 1: Persistent Volume (Recommended)

Mount a persistent volume for the database file so it survives container restarts and deployments.

**Kamal (`config/deploy.yml`):**
```yaml
volumes:
  - "trackdown_data:/rails/db/geodata"
```

Then configure the database path:
```ruby
# config/initializers/trackdown.rb
config.database_path = Rails.root.join('db', 'geodata', 'GeoLite2-City.mmdb').to_s
```

**Docker Compose:**
```yaml
services:
  app:
    volumes:
      - trackdown_data:/rails/db/geodata

volumes:
  trackdown_data:
```

### Option 2: Download on Container Start

If you prefer not to use volumes, download the database when the container starts. Add to your entrypoint or a post-deploy hook:

```bash
# In your entrypoint.sh or deploy hook
bin/rails runner "Trackdown.update_database unless File.exist?(Trackdown.configuration.database_path)"
```

Or create a job that runs on boot:

```ruby
# config/initializers/trackdown_boot.rb
Rails.application.config.after_initialize do
  if Rails.env.production? && !File.exist?(Trackdown.configuration.database_path)
    Trackdown.update_database
  end
end
```

> [!WARNING]
> Option 2 adds startup time (~10-30 seconds) on fresh deploys and requires network access during boot. A persistent volume is more reliable for production.

### Background Jobs Consideration

When using background job processors (Sidekiq, SolidQueue, GoodJob), geolocation lookups in jobs **cannot use Cloudflare or CloudFront headers** because there is no HTTP request. These jobs fall back to MaxMind automatically under `:auto`.

Make sure MaxMind is properly configured if you're doing geolocation in background jobs:

```ruby
# This works in controllers (has request)
Trackdown.locate(ip, request: request)  # Uses one verified CDN provider if available

# This works in background jobs (no request)
Trackdown.locate(ip)  # Falls back to MaxMind
```

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rake test` to run the Minitest tests.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/trackdown. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
