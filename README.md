# 📍 `trackdown` - Ruby gem to geolocate IPs (MaxMind BYOK)

`trackdown` is a Ruby gem that provides simple & straightforward IP geolocation functionality using MaxMind databases. Just bring your keys and start geolocating IPs.

Given an IP, it gives you the corresponding:
- 🗺️ Country (two-letter country code + country name)
- 📍 City
- 🇺🇸 Emoji flag of the country

`trackdown` is BYOK (Bring Your Own Key) – you'll need your own MaxMind keys for it to work. [TODO: add link to where to get it]

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
  config.maxmind_license_key = 'your_license_key_here'
  config.maxmind_account_id = 'your_account_id_here'
end
```

The generator also creates a rake task for updating the MaxMind database and adds a weekly schedule to `config/schedule.rb` for automatic updates.

## Usage

To geolocate an IP address:

```ruby
Trackdown.locate('8.8.8.8')
# => { country_code: 'US', city: 'Mountain View', emoji_flag: '🇺🇸' }
```

You can also do things like:
```ruby
Trackdown.locate('8.8.8.8').emoji
# => '🇺🇸'
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
