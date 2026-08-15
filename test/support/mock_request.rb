# frozen_string_literal: true

module TestHelpers
  module MockRequest
    # A bare Rack-ish request carrying exactly the env you hand it.
    def mock_request(env = {})
      request = Object.new
      request.define_singleton_method(:env) { env }
      request
    end

    # Teach Trackdown how this host proves a request really came through its CDN.
    def verify_trusted_cdn_path_with_header(provider_name: :cloudflare,
                                            name: 'HTTP_X_ORIGIN_SECRET', value: 'shared-secret')
      Trackdown.configure do |config|
        config.verify_request_came_through_trusted_cdn_path_with(provider_name) do |request|
          request.env[name] == value
        end
      end
    end

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

    def mock_cloudflare_request_with_all_headers(connecting_ip: nil)
      request = mock_cloudflare_request(
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
      request.env['HTTP_CF_CONNECTING_IP'] = connecting_ip if connecting_ip
      request
    end

    def mock_request_without_cloudflare
      request = Object.new
      request.define_singleton_method(:env) { {} }
      request
    end

    def mock_cloudfront_request(country: 'US', city: 'San Francisco',
                                region: nil, region_code: nil,
                                latitude: nil, longitude: nil,
                                timezone: nil, postal_code: nil,
                                metro_code: nil, viewer_address: nil)
      request = Object.new
      env = {}
      env['HTTP_CLOUDFRONT_VIEWER_COUNTRY'] = country unless country.nil?
      env['HTTP_CLOUDFRONT_VIEWER_CITY'] = city unless city.nil?
      env['HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION_NAME'] = region if region
      env['HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION'] = region_code if region_code
      env['HTTP_CLOUDFRONT_VIEWER_LATITUDE'] = latitude if latitude
      env['HTTP_CLOUDFRONT_VIEWER_LONGITUDE'] = longitude if longitude
      env['HTTP_CLOUDFRONT_VIEWER_TIME_ZONE'] = timezone if timezone
      env['HTTP_CLOUDFRONT_VIEWER_POSTAL_CODE'] = postal_code if postal_code
      env['HTTP_CLOUDFRONT_VIEWER_METRO_CODE'] = metro_code if metro_code
      env['HTTP_CLOUDFRONT_VIEWER_ADDRESS'] = viewer_address if viewer_address
      request.define_singleton_method(:env) { env }
      request
    end

    def mock_cloudfront_request_with_all_headers(viewer_address: nil)
      mock_cloudfront_request(
        country: 'US',
        city: 'San Francisco',
        region: 'California',
        region_code: 'CA',
        latitude: '37.7749',
        longitude: '-122.4194',
        timezone: 'America/Los_Angeles',
        postal_code: '94107',
        metro_code: '807',
        viewer_address: viewer_address
      )
    end

    # Mock a CloudFront request where Viewer-Address (IP:port) matches the client IP
    def mock_cloudfront_request_with_matching_ip(ip:, port: '46532', country: 'US', city: 'San Francisco')
      mock_cloudfront_request(country: country, city: city, viewer_address: "#{ip}:#{port}")
    end

    # Mock a CloudFront request where Viewer-Address differs from the IP we're geolocating
    # (simulates an upstream proxy before CloudFront)
    def mock_cloudfront_request_with_proxy(proxy_ip:, port: '46532', proxy_country: 'US', proxy_city: 'Ashburn')
      mock_cloudfront_request(country: proxy_country, city: proxy_city, viewer_address: "#{proxy_ip}:#{port}")
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
          'metro_code' => 807,
          'accuracy_radius' => 20
        },
        'postal' => {
          'code' => '94107'
        }
      }
    end
  end
end
