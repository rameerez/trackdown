# 📍 `trackdown` - Ruby gem to geolocate IPs (MaxMind BYOK)

`trackdown` is a Ruby gem that easily allows you to geolocate IP addresses. It's a simple, convenient wrapper on top of MaxMind. Just bring your own MaxMind keys, and you're good to go. It keeps your MaxMind database updated regularly, and it offers a handy API for Rails applications to fetch country, city, and emoji flag information for any IP address.

Given an IP, it gives you the corresponding:
- 🗺️ Country (two-letter country code + country name)
- 📍 City
- 🇺🇸 Emoji flag of the country

`trackdown` is BYOK (Bring Your Own Key) – you'll need your own MaxMind keys for it to work. It's your responsibility to make sure your app complies with the license for the MaxMind database you're using. Get a MaxMind account and license key at [MaxMind](https://www.maxmind.com/).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'trackdown'
```

And then execute:

```bash
bundle install
```

## Setup

First, run the installation generator:

```bash
rails generate trackdown:install
```

This will create an initializer file at `config/initializers/trackdown.rb`. Open this file and add your MaxMind license key and account ID:

```ruby
Trackdown.configure do |config|
  # Tip: do not write your plaintext keys in the code, use Rails.application.credentials instead
  config.maxmind_account_id = 'your_account_id_here'
  config.maxmind_license_key = 'your_license_key_here'
end
```

> [!TIP]
> To get your MaxMind account ID and license key, you need to create an account at [MaxMind](https://www.maxmind.com/) and get a license key.

You can also configure the path where the MaxMind database will be stored. By default, it will be stored at `db/GeoLite2-City.mmdb`:

```ruby
config.database_path = Rails.root.join('db', 'GeoLite2-City.mmdb').to_s
```

The generator also creates a `TrackdownDatabaseRefreshJob` job for regularly updating the MaxMind database. You can just get a database the first time and just keep using it, but the information will get outdated and some IPs will become stale or inaccurate.

To keep your IP geolocation accurate, you need to make sure the `TrackdownDatabaseRefreshJob` runs regularly. How you do that, exactly, depends on the queueing system you're using.

If you're using `solid_queue` (the Rails 8 default), you can easily add it to your schedule in the `config/recurring.yml` file like this:
```yaml
production:
  refresh_maxmind_database:
    class: TrackdownDatabaseRefreshJob
    queue: default
    schedule: every day at 4am US/Pacific
```

After setting everything up, you can run the following command to update the MaxMind database / get the first fresh copy of it:

```ruby
Trackdown.update_database
```

## Usage

To geolocate an IP address:

```ruby
Trackdown.locate('8.8.8.8').country
# => 'United States'
```

You can also do things like:
```ruby
Trackdown.locate('8.8.8.8').emoji
# => '🇺🇸'
```

In fact, there are a few methods you can use:
```ruby
result = Trackdown.locate('8.8.8.8')

result.country_code    # => 'US'
result.country_name    # => 'United States'
result.country         # => 'United States' (alias for country_name)
result.city            # => 'Mountain View'
result.flag_emoji      # => '🇺🇸'
result.emoji           # => '🇺🇸' (alias for flag_emoji)
```

If you prefer, you can also get all the information as a hash:
```ruby
result.to_h
# => {
#      country_code: 'US',
#      country_name: 'United States',
#      city: 'Mountain View',
#      flag_emoji: '🇺🇸'
#    }
```

To manually update the MaxMind IP database:
```ruby
Trackdown.update_database
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/trackdown. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
