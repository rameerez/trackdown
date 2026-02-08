# frozen_string_literal: true

module TestHelpers
  module MockRequest
    def mock_cloudflare_request(country: 'US', city: 'San Francisco',
                                region: nil, region_code: nil,
                                latitude: nil, longitude: nil,
                                timezone: nil, continent: nil)
      request = Object.new
      env = {
        'HTTP_CF_IPCOUNTRY' => country,
        'HTTP_CF_IPCITY' => city
      }
      env['HTTP_CF_REGION'] = region if region
      env['HTTP_CF_REGION_CODE'] = region_code if region_code
      env['HTTP_CF_LATITUDE'] = latitude if latitude
      env['HTTP_CF_LONGITUDE'] = longitude if longitude
      env['HTTP_CF_TIMEZONE'] = timezone if timezone
      env['HTTP_CF_CONTINENT'] = continent if continent
      request.define_singleton_method(:env) { env }
      request
    end

    def mock_cloudflare_request_with_all_headers
      mock_cloudflare_request(
        country: 'US',
        city: 'San Francisco',
        region: 'California',
        region_code: 'CA',
        latitude: '37.7749',
        longitude: '-122.4194',
        timezone: 'America/Los_Angeles',
        continent: 'NA'
      )
    end

    def mock_request_without_cloudflare
      request = Object.new
      request.define_singleton_method(:env) { {} }
      request
    end

    def mock_request_with_xx_country
      request = Object.new
      env = { 'HTTP_CF_IPCOUNTRY' => 'XX' }
      request.define_singleton_method(:env) { env }
      request
    end

    def mock_request_with_tor
      request = Object.new
      env = { 'HTTP_CF_IPCOUNTRY' => 'T1' }
      request.define_singleton_method(:env) { env }
      request
    end

    def full_maxmind_record
      {
        'country' => {
          'iso_code' => 'US',
          'names' => { 'en' => 'United States' }
        },
        'city' => {
          'names' => { 'en' => 'San Francisco' }
        },
        'subdivisions' => [
          {
            'iso_code' => 'CA',
            'names' => { 'en' => 'California' }
          }
        ],
        'continent' => {
          'code' => 'NA',
          'names' => { 'en' => 'North America' }
        },
        'location' => {
          'latitude' => 37.7749,
          'longitude' => -122.4194,
          'time_zone' => 'America/Los_Angeles'
        }
      }
    end
  end
end
