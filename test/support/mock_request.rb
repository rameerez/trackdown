# frozen_string_literal: true

module TestHelpers
  module MockRequest
    def mock_cloudflare_request(country: 'US', city: 'San Francisco')
      request = Object.new
      env = {
        'HTTP_CF_IPCOUNTRY' => country,
        'HTTP_CF_IPCITY' => city
      }
      request.define_singleton_method(:env) { env }
      request
    end

    def mock_request_without_cloudflare
      request = Object.new
      request.define_singleton_method(:env) { {} }
      request
    end

    def mock_request_with_xx_country
      request = Object.new
      env = {'HTTP_CF_IPCOUNTRY' => 'XX'}
      request.define_singleton_method(:env) { env }
      request
    end

    def mock_request_with_tor
      request = Object.new
      env = {'HTTP_CF_IPCOUNTRY' => 'T1'}
      request.define_singleton_method(:env) { env }
      request
    end
  end
end
