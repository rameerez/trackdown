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

Add this line to your application's Gemfile:

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
# => 'United States'
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
# => 'United States'
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
result.country_name    # => 'United States'
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

If you prefer, you can also get all the information as a hash:

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

Trackdown reads these headers directly from the request with zero overhead — no database lookups, no external API calls.

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

- `CloudFront-Viewer-Country` is validated as an assigned ISO 3166-1 alpha-2 code before CloudFront is considered available.
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

Downloads the [GeoLite2-City](https://dev.maxmind.com/geoip/docs/databases/city-and-country/) database to your server and performs local lookups using connection pooling for performance. All fields (`country`, `city`, `region`, `continent`, `timezone`, `latitude`, `longitude`, `postal_code`, `metro_code`) are extracted from the database record.


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
