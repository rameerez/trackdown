# frozen_string_literal: true

# Drives the public API of an *installed* trackdown gem, with only its declared
# dependencies available.
#
# The unit suite runs against lib/ inside the development bundle, where dozens of
# gems happen to be loadable. This does not: it is the check that catches a
# `require` that only ever worked because something else in the Gemfile pulled it
# in, and it is how the oldest Ruby the gemspec supports gets tested at all —
# the test toolchain itself needs a newer one.
#
# Run it against an isolated install:
#
#   gem build trackdown.gemspec -o trackdown.gem
#   gem install --install-dir /tmp/isolated --no-document trackdown.gem
#   GEM_HOME=/tmp/isolated GEM_PATH=/tmp/isolated ruby test/smoke/packaged_gem.rb

require 'stringio'
require 'trackdown'

RESULTS = []

def check(label, actual, expected)
  passed = actual == expected
  RESULTS << passed
  detail = passed ? '' : "  (expected #{expected.inspect})"
  puts "  #{passed ? 'ok  ' : 'FAIL'} #{label}: #{actual.inspect}#{detail}"
end

def request_with(env)
  Object.new.tap { |request| request.define_singleton_method(:env) { env } }
end

def quietly
  original = $stderr
  $stderr = StringIO.new
  yield
ensure
  $stderr = original
end

puts "trackdown #{Trackdown::VERSION} on Ruby #{RUBY_VERSION}"

# --- Cloudflare, corroborated by CF-Connecting-IP -----------------------------
cloudflare = request_with(
  'HTTP_CF_IPCOUNTRY' => 'US', 'HTTP_CF_IPCITY' => 'San Francisco',
  'HTTP_CF_IPLATITUDE' => '37.7749', 'HTTP_CF_CONNECTING_IP' => '203.0.113.9'
)
result = Trackdown.locate('203.0.113.9', request: cloudflare)

check('country code', result.country_code, 'US')
check('city', result.city, 'San Francisco')
check('latitude', result.latitude, 37.7749)
check('flag', result.flag_emoji, '🇺🇸')
check('provider', result.provider_name, :cloudflare)
check('source', result.provider_source, :cloudflare_request_headers)
check('available', result.available?, true)
check('estimated', result.estimated?, true)
check('resolved_at is a Time', result.resolved_at.is_a?(Time), true)
check('unverified without a verifier', result.source_trust, :unverified)
check('no invented accuracy', result.accuracy_radius_in_kilometers, nil)
check('no invented database', result.database_sha256, nil)

# --- Serialization ------------------------------------------------------------
check('default to_h shape', result.to_h.keys, Trackdown::LocationResult::DEFAULT_FIELDS)
check('default to_h key count', result.to_h.length, 13)
check('provenance opt-in', result.to_h(include_provenance: true)[:provider_name], :cloudflare)
check('digest stays opt-in', result.to_h(include_provenance: true).key?(:database_sha256), false)
check('allowlist', result.to_h(only: %i[country_code city]), { country_code: 'US', city: 'San Francisco' })
check('country_info can be dropped', result.to_h(include_country_info: false).key?(:country_info), false)
check('unknown field raises',
      begin
        result.to_h(only: %i[nope])
        :no_error
      rescue ArgumentError
        :raised
      end, :raised)

# --- Host-verified source trust ----------------------------------------------
Trackdown.configure do |config|
  config.verify_request_came_through_trusted_cloudflare_path_with do |request|
    request.env['HTTP_X_ORIGIN_SECRET'] == 'shared-secret'
  end
end
check('still unverified without the secret', Trackdown.locate('203.0.113.9', request: cloudflare).source_trust,
      :unverified)
cloudflare.env['HTTP_X_ORIGIN_SECRET'] = 'shared-secret'
check('host verified with the secret', Trackdown.locate('203.0.113.9', request: cloudflare).source_trust,
      :host_verified)

# --- CloudFront, and trust that does not cross CDNs ---------------------------
cloudfront = request_with(
  'HTTP_CLOUDFRONT_VIEWER_COUNTRY' => 'GB', 'HTTP_CLOUDFRONT_VIEWER_CITY' => 'London',
  'HTTP_CLOUDFRONT_VIEWER_ADDRESS' => '203.0.113.9:46532', 'HTTP_X_ORIGIN_SECRET' => 'shared-secret'
)
cloudfront_result = Trackdown.locate('203.0.113.9', request: cloudfront)
check('cloudfront wins', cloudfront_result.provider_name, :cloudfront)
check('cloudfront city', cloudfront_result.city, 'London')
check('a cloudflare verifier cannot vouch for cloudfront', cloudfront_result.source_trust, :unverified)

# --- Country codes ------------------------------------------------------------
tor = Trackdown.locate('203.0.113.9',
                       request: request_with('HTTP_CF_IPCOUNTRY' => 'T1', 'HTTP_CF_CONNECTING_IP' => '203.0.113.9'))
check('tor is unavailable', tor.unavailable_reason, :provider_returned_unknown_country)
check('tor keeps its code', tor.country_code, 'T1')
check('tor has no broken flag', tor.flag_emoji, '🏳️')

kosovo = Trackdown.locate('203.0.113.9', request: request_with('HTTP_CF_IPCOUNTRY' => 'XK',
                                                               'HTTP_CF_IPCITY' => 'Pristina',
                                                               'HTTP_CF_CONNECTING_IP' => '203.0.113.9'))
check('an unfamiliar country code is still an answer', kosovo.available?, true)
check('kosovo city', kosovo.city, 'Pristina')

# --- Untrusted input ----------------------------------------------------------
hostile = Trackdown.locate('203.0.113.9', request: request_with('HTTP_CF_IPCOUNTRY' => 'US',
                                                                'HTTP_CF_IPLATITUDE' => '0x10',
                                                                'HTTP_CF_CONNECTING_IP' => '203.0.113.9'))
check('hexadecimal latitude rejected', hostile.latitude, nil)

# --- No provider at all -------------------------------------------------------
Trackdown.configuration.database_path = '/nonexistent/GeoLite2-City.mmdb'
nothing = quietly { Trackdown.locate('8.8.8.8') }
check('no provider reason', nothing.unavailable_reason, :no_provider_available)
check('no provider name', nothing.provider_name, nil)
check('country_name still Unknown', nothing.country_name, 'Unknown')
check('city still Unknown', nothing.city, 'Unknown')

check('private addresses rejected by default',
      begin
        Trackdown.locate('192.168.1.1')
        :no_error
      rescue Trackdown::IpValidator::InvalidIpError
        :rejected
      end, :rejected)

failures = RESULTS.count(false)
puts failures.zero? ? "\nALL OK (#{RESULTS.length} checks)" : "\n*** #{failures} of #{RESULTS.length} FAILED ***"
exit(failures.zero? ? 0 : 1)
