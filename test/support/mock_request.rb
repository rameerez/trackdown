# frozen_string_literal: true

module TestHelpers
  module MockRequest
    def mock_cloudflare_request(country: 'US', city: 'San Francisco',
                                region: nil, region_code: nil,
                                latitude: nil, longitude: nil,
                                timezone: nil, continent: nil,
                                postal_code: nil, metro_code: nil)
      request = Object.new
      env = {
        'HTTP_CF_IPCOUNTRY' => country,
        'HTTP_CF_IPCITY' => city
      }
      env['HTTP_CF_REGION'] = region if region
      env['HTTP_CF_REGION_CODE'] = region_code if region_code
      env['HTTP_CF_IPLATITUDE'] = latitude if latitude
      env['HTTP_CF_IPLONGITUDE'] = longitude if longitude
      env['HTTP_CF_TIMEZONE'] = timezone if timezone
      env['HTTP_CF_IPCONTINENT'] = continent if continent
      env['HTTP_CF_POSTAL_CODE'] = postal_code if postal_code
      env['HTTP_CF_METRO_CODE'] = metro_code if metro_code
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
        continent: 'NA',
        postal_code: '94107',
        metro_code: '807'
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

    # Mock a request where the CF-Connecting-IP matches the IP we're geolocating
    def mock_cloudflare_request_with_matching_ip(ip:, country: 'US', city: 'San Francisco')
      request = Object.new
      env = {
        'HTTP_CF_IPCOUNTRY' => country,
        'HTTP_CF_IPCITY' => city,
        'HTTP_CF_CONNECTING_IP' => ip
      }
      request.define_singleton_method(:env) { env }
      request
    end

    # Mock a request where CF-Connecting-IP differs from the IP we're geolocating
    # This simulates an upstream proxy before Cloudflare
    def mock_cloudflare_request_with_proxy(proxy_ip:, proxy_country: 'US', proxy_city: 'Ashburn')
      request = Object.new
      env = {
        'HTTP_CF_IPCOUNTRY' => proxy_country,
        'HTTP_CF_IPCITY' => proxy_city,
        'HTTP_CF_CONNECTING_IP' => proxy_ip  # Cloudflare saw the proxy, not the client
      }
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
          'time_zone' => 'America/Los_Angeles',
          'metro_code' => 807
        },
        'postal' => {
          'code' => '94107'
        }
      }
    end
  end
end
