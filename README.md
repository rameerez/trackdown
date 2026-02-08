# 📍 `trackdown` - Ruby gem to geolocate IPs

> [!TIP]
> **🚀 Ship your next Rails app 10x faster!** I've built **[RailsFast](https://railsfast.com/?ref=trackdown)**, a production-ready Rails boilerplate template that comes with everything you need to launch a software business in days, not weeks. Go [check it out](https://railsfast.com/?ref=trackdown)!

`trackdown` is a Ruby gem that allows you to geolocate IP addresses easily. It works out-of-the-box with **Cloudflare** (zero config!); and it's also a simple, convenient wrapper on top of **MaxMind** (just bring your own MaxMind key, and you're good to go!). `trackdown` offers a clean API for Rails applications to fetch country, city, region, continent, timezone, coordinates, and emoji flag information for any IP address.

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

## Two ways to use `trackdown`

### Option 1: Cloudflare (recommended, zero config)

If your app is behind Cloudflare, you can use `trackdown` with **zero configuration**:
- No API keys needed
- No database downloads
- No external dependencies
- Instant lookups from Cloudflare headers

Just enable "IP Geolocation" in your Cloudflare dashboard and you're done! We automatically check for the Cloudflare headers in the context of a `request` and provide you with the IP geo data.

### Option 2: MaxMind (BYOK - Bring Your Own Key)

For apps not behind Cloudflare, offline apps, non-Rails apps, or as a fallback, use MaxMind:
- Requires MaxMind account and license key
- Requires downloading and maintaining a local database
- Works offline once database is downloaded
- Get started at [MaxMind](https://www.maxmind.com/)

### Option 3: Auto

By default, `trackdown` uses **`:auto` mode** which tries Cloudflare first and falls back to MaxMind automatically.

> [!NOTE]
> Trackdown fails gracefully. If no provider is available (no Cloudflare headers, no MaxMind database), it returns `'Unknown'` instead of raising an error, so your app doesn't crash due to a missing geolocation provider.


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
    schedule: every Saturday at 4am US/Pacific
```

> [!NOTE]
> MaxMind updates their databases [every Tuesday and Friday](https://dev.maxmind.com/geoip/geoip2/geoip2-update-process/).

## Usage

### With Cloudflare (recommended when available)

```ruby
# In your controller - pass the request object
result = Trackdown.locate(request.remote_ip, request: request)
result.country
# => 'United States'
```

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
result.city            # => 'Mountain View' (from MaxMind or Cloudflare's "Add visitor location headers")
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
> The `region`, `region_code`, `continent`, `timezone`, `latitude`, `longitude`, `postal_code`, and `metro_code` fields require Cloudflare's "Add visitor location headers" Managed Transform to be enabled, or a MaxMind GeoLite2-City database. These fields return `nil` when not available.

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
  # :auto - Try Cloudflare first, fall back to MaxMind (default, recommended)
  # :cloudflare - Only use Cloudflare headers
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

When you enable "IP Geolocation" in Cloudflare, they add the `CF-IPCountry` header to every request. If you enable "Add visitor location headers" (via Managed Transforms), you also get `CF-IPCity`, `CF-IPContinent`, `CF-IPLatitude`, `CF-IPLongitude`, `CF-Region`, `CF-Region-Code`, `CF-Metro-Code`, `CF-Postal-Code`, and `CF-Timezone`.

Trackdown reads these headers directly from the request with zero overhead, and no database lookups.

### MaxMind Provider

Downloads the GeoLite2-City database to your server and performs local lookups using connection pooling for performance.


## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rake test` to run the Minitest tests.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/trackdown. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
