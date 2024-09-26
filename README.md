# 📍 `trackdown` - Ruby gem to geolocate IPs (MaxMind BYOK)

`trackdown` is a Ruby gem that provides simple & straightforward IP geolocation functionality using MaxMind databases. Just bring your own MaxMind keys, and start geolocating IPs.

Given an IP, it gives you the corresponding:
- 🗺️ Country (two-letter country code + country name)
- 📍 City
- 🇺🇸 Emoji flag of the country

`trackdown` is BYOK (Bring Your Own Key) – you'll need your own MaxMind keys for it to work. It's your responsibility to make sure your app complies with the license for the MaxMind database you're using. [TODO: add link to where to get it]

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
  config.maxmind_license_key = 'your_license_key_here'
  config.maxmind_account_id = 'your_account_id_here'
end
```

The generator also creates a rake task for updating the MaxMind database and adds a weekly schedule to `config/schedule.rb` for automatic updates.

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
