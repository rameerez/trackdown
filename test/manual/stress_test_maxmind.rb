#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Stress test for Trackdown MaxMind provider with a real GeoLite2-City database.
#
# Usage:
#   ruby test/stress_test_maxmind.rb [path_to_mmdb]
#
# If no path given, defaults to ../licenseseat/db/GeoLite2-City.mmdb
#

require "bundler/setup"
require "trackdown"
require "benchmark"

DB_PATH = ARGV[0] || File.expand_path("../../licenseseat/db/GeoLite2-City.mmdb", __dir__)

unless File.exist?(DB_PATH)
  abort "MaxMind database not found at: #{DB_PATH}\nPass the path as an argument: ruby test/stress_test_maxmind.rb /path/to/GeoLite2-City.mmdb"
end

Trackdown.configure do |config|
  config.provider = :maxmind
  config.database_path = DB_PATH
end

# ---------------------------------------------------------------------------
# Test IPs — diverse global coverage
# ---------------------------------------------------------------------------
TEST_IPS = {
  # IP => [expected_country_code, expected_city_or_nil, description]
  "8.8.8.8"         => ["US", nil, "Google DNS (US)"],
  "8.8.4.4"         => ["US", nil, "Google DNS secondary (US)"],
  "1.1.1.1"         => ["AU", nil, "Cloudflare DNS (AU)"],
  "9.9.9.9"         => ["US", nil, "Quad9 DNS (US)"],
  "208.67.222.222"  => ["US", nil, "OpenDNS (US)"],
  "185.199.108.153" => ["US", nil, "GitHub Pages (US)"],
  "104.16.132.229"  => ["US", nil, "Cloudflare (US)"],
  "151.101.1.140"   => ["US", nil, "Reddit/Fastly (US)"],
  "198.41.0.4"      => ["US", nil, "Root DNS A (US)"],

  # Europe
  "81.2.69.144"     => ["GB", nil, "UK IP"],
  "2.17.68.0"       => [nil,  nil, "Akamai EU"],
  "195.54.42.1"     => [nil,  nil, "DE IP"],
  "77.88.55.60"     => ["RU", nil, "Yandex DNS (RU)"],
  "176.103.130.130" => [nil,  nil, "AdGuard DNS (EU)"],

  # Asia
  "203.208.60.1"    => ["CN", nil, "China IP"],
  "180.76.76.76"    => ["CN", nil, "Baidu DNS (CN)"],
  "61.135.169.125"  => ["CN", nil, "Baidu web (CN)"],
  "119.29.29.29"    => ["CN", nil, "DNSPod (CN)"],
  "1.0.0.1"         => ["AU", nil, "Cloudflare secondary"],
  "202.12.27.33"    => ["JP", nil, "Root DNS M (JP)"],
  "168.126.63.1"    => ["KR", nil, "KT DNS (KR)"],
  "103.224.182.250" => [nil,  nil, "IN IP"],

  # South America
  "200.160.2.3"     => ["BR", nil, "BR IP"],
  "190.0.224.1"     => [nil,  nil, "AR IP"],

  # Africa
  "196.216.2.1"     => [nil,  nil, "ZA IP"],

  # Oceania
  "210.10.2.1"      => [nil,  nil, "AU/NZ IP"],

  # Anycast / CDN
  "13.107.42.14"    => ["US", nil, "Microsoft (US)"],
  "142.250.185.206" => ["US", nil, "Google (US)"],
  "157.240.1.35"    => ["US", nil, "Facebook (US)"],
}.freeze

ALL_FIELDS = %i[
  country_code country_name city flag_emoji
  region region_code continent timezone
  latitude longitude postal_code metro_code
].freeze

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def separator(char = "=", width = 78)
  puts char * width
end

def section(title)
  puts
  separator
  puts "  #{title}"
  separator
  puts
end

def pass(msg)
  puts "  \e[32m✓\e[0m #{msg}"
end

def warn_msg(msg)
  puts "  \e[33m⚠\e[0m #{msg}"
end

def fail_msg(msg)
  puts "  \e[31m✗\e[0m #{msg}"
end

# ---------------------------------------------------------------------------
# 1. Basic lookups — every IP, verify structure
# ---------------------------------------------------------------------------
section "1. BASIC LOOKUPS — #{TEST_IPS.size} IPs"

results = {}
errors = []
field_stats = Hash.new(0)

TEST_IPS.each do |ip, (expected_cc, _expected_city, desc)|
  begin
    result = Trackdown.locate(ip)
    results[ip] = result

    # Must return a LocationResult
    unless result.is_a?(Trackdown::LocationResult)
      fail_msg "#{ip} (#{desc}): expected LocationResult, got #{result.class}"
      errors << ip
      next
    end

    # Count non-nil fields
    ALL_FIELDS.each { |f| field_stats[f] += 1 if result.send(f) }

    # Check expected country code if we specified one
    if expected_cc && result.country_code != expected_cc
      warn_msg "#{ip} (#{desc}): expected CC=#{expected_cc}, got CC=#{result.country_code}"
    else
      detail = [result.country_code, result.city, result.region].compact.join(", ")
      pass "#{ip.ljust(18)} → #{detail.ljust(40)} (#{desc})"
    end
  rescue => e
    fail_msg "#{ip} (#{desc}): #{e.class}: #{e.message}"
    errors << ip
  end
end

puts
puts "  Looked up #{TEST_IPS.size} IPs, #{errors.size} errors"

# ---------------------------------------------------------------------------
# 2. Field coverage report
# ---------------------------------------------------------------------------
section "2. FIELD COVERAGE (across #{results.size} successful lookups)"

ALL_FIELDS.each do |field|
  count = field_stats[field]
  pct = (count.to_f / results.size * 100).round(1)
  bar = "#" * (pct / 2).to_i
  status = pct > 50 ? "\e[32m" : (pct > 20 ? "\e[33m" : "\e[31m")
  puts "  #{field.to_s.ljust(16)} #{status}#{count.to_s.rjust(3)}/#{results.size} (#{pct.to_s.rjust(5)}%)\e[0m  #{bar}"
end

# ---------------------------------------------------------------------------
# 3. to_h round-trip
# ---------------------------------------------------------------------------
section "3. to_h ROUND-TRIP VERIFICATION"

sample_ip = "8.8.8.8"
result = results[sample_ip]
if result
  h = result.to_h
  expected_keys = ALL_FIELDS + [:country_info]
  missing = expected_keys - h.keys
  extra = h.keys - expected_keys

  if missing.empty? && extra.empty?
    pass "to_h returns all #{expected_keys.size} expected keys"
  else
    fail_msg "to_h missing keys: #{missing}" unless missing.empty?
    fail_msg "to_h extra keys: #{extra}" unless extra.empty?
  end

  # Verify values match accessors
  match_count = 0
  ALL_FIELDS.each do |f|
    if h[f] == result.send(f)
      match_count += 1
    else
      fail_msg "to_h[:#{f}] = #{h[f].inspect} != accessor #{result.send(f).inspect}"
    end
  end
  pass "All #{match_count} field values match between to_h and accessors" if match_count == ALL_FIELDS.size
else
  fail_msg "No result for #{sample_ip} to test to_h"
end

# ---------------------------------------------------------------------------
# 4. Aliases
# ---------------------------------------------------------------------------
section "4. ALIAS VERIFICATION"

if result
  [
    [:country, :country_name],
    [:emoji, :flag_emoji],
    [:emoji_flag, :flag_emoji],
    [:country_flag, :flag_emoji],
  ].each do |ali, original|
    if result.send(ali) == result.send(original)
      pass "#{ali} == #{original}"
    else
      fail_msg "#{ali} (#{result.send(ali).inspect}) != #{original} (#{result.send(original).inspect})"
    end
  end
end

# ---------------------------------------------------------------------------
# 5. country_info
# ---------------------------------------------------------------------------
section "5. COUNTRY_INFO (ISO3166)"

if result
  info = result.country_info
  if info
    pass "country_info returned ISO3166::Country for #{result.country_code}"
    pass "  name: #{info.common_name || info.name}" if info.respond_to?(:common_name)
    pass "  alpha3: #{info.alpha3}" if info.respond_to?(:alpha3)
    pass "  currency_code: #{info.currency_code}" if info.respond_to?(:currency_code)
  else
    fail_msg "country_info returned nil for #{result.country_code}"
  end
end

# ---------------------------------------------------------------------------
# 6. Coordinate validation
# ---------------------------------------------------------------------------
section "6. COORDINATE VALIDATION"

coord_ok = 0
coord_warn = 0
results.each do |ip, r|
  next unless r.latitude && r.longitude

  if r.latitude.between?(-90, 90) && r.longitude.between?(-180, 180)
    coord_ok += 1
  else
    warn_msg "#{ip}: lat=#{r.latitude}, lon=#{r.longitude} OUT OF RANGE"
    coord_warn += 1
  end
end

pass "#{coord_ok} IPs with valid coordinate ranges" if coord_ok > 0
warn_msg "#{coord_warn} IPs with out-of-range coordinates" if coord_warn > 0
puts "  (#{results.size - coord_ok - coord_warn} IPs had no coordinates)" if (results.size - coord_ok - coord_warn) > 0

# ---------------------------------------------------------------------------
# 7. Data type validation
# ---------------------------------------------------------------------------
section "7. DATA TYPE VALIDATION"

type_errors = 0
results.each do |ip, r|
  checks = {
    country_code: [String, NilClass],
    country_name: [String],
    city:         [String],
    flag_emoji:   [String],
    region:       [String, NilClass],
    region_code:  [String, NilClass],
    continent:    [String, NilClass],
    timezone:     [String, NilClass],
    latitude:     [Float, Integer, NilClass],
    longitude:    [Float, Integer, NilClass],
    postal_code:  [String, NilClass],
    metro_code:   [String, NilClass],
  }
  checks.each do |field, allowed_types|
    val = r.send(field)
    unless allowed_types.any? { |t| val.is_a?(t) }
      fail_msg "#{ip}.#{field}: expected #{allowed_types.join('|')}, got #{val.class} (#{val.inspect})"
      type_errors += 1
    end
  end
end

if type_errors == 0
  pass "All fields have correct types across #{results.size} results"
else
  fail_msg "#{type_errors} type errors found"
end

# ---------------------------------------------------------------------------
# 8. Performance benchmark
# ---------------------------------------------------------------------------
section "8. PERFORMANCE BENCHMARK"

# Warm up the pool
Trackdown.locate("8.8.8.8")

iterations = 1000
ips = TEST_IPS.keys

time = Benchmark.realtime do
  iterations.times do
    ip = ips.sample
    Trackdown.locate(ip)
  end
end

avg_ms = (time / iterations * 1000).round(3)
ops_sec = (iterations / time).round(0)
puts "  #{iterations} lookups in #{time.round(3)}s"
puts "  Average: #{avg_ms}ms per lookup"
puts "  Throughput: #{ops_sec} lookups/sec"

if avg_ms < 1
  pass "Sub-millisecond lookups"
elsif avg_ms < 5
  pass "Fast lookups (< 5ms)"
else
  warn_msg "Slow lookups (#{avg_ms}ms avg)"
end

# ---------------------------------------------------------------------------
# 9. Concurrent access
# ---------------------------------------------------------------------------
section "9. CONCURRENT ACCESS (thread safety)"

threads = 10
per_thread = 100
concurrent_errors = []

thread_pool = threads.times.map do |t|
  Thread.new do
    per_thread.times do
      ip = ips.sample
      result = Trackdown.locate(ip)
      unless result.is_a?(Trackdown::LocationResult)
        concurrent_errors << "Thread #{t}: #{ip} returned #{result.class}"
      end
    end
  rescue => e
    concurrent_errors << "Thread #{t}: #{e.class}: #{e.message}"
  end
end

thread_pool.each(&:join)

if concurrent_errors.empty?
  pass "#{threads * per_thread} concurrent lookups across #{threads} threads — no errors"
else
  concurrent_errors.each { |e| fail_msg e }
end

# ---------------------------------------------------------------------------
# 10. Edge cases
# ---------------------------------------------------------------------------
section "10. EDGE CASES"

# Private IPs should raise
begin
  Trackdown.locate("127.0.0.1")
  fail_msg "127.0.0.1 should have raised (private IP rejection enabled)"
rescue Trackdown::Error => e
  pass "127.0.0.1 correctly rejected: #{e.message}"
end

begin
  Trackdown.locate("10.0.0.1")
  fail_msg "10.0.0.1 should have raised (private IP rejection enabled)"
rescue Trackdown::Error => e
  pass "10.0.0.1 correctly rejected: #{e.message}"
end

begin
  Trackdown.locate("192.168.1.1")
  fail_msg "192.168.1.1 should have raised (private IP rejection enabled)"
rescue Trackdown::Error => e
  pass "192.168.1.1 correctly rejected: #{e.message}"
end

# With private IP rejection disabled
Trackdown.configuration.reject_private_ips = false
begin
  result = Trackdown.locate("127.0.0.1")
  if result.country_code.nil?
    pass "127.0.0.1 with rejection disabled: returns unknown (nil country_code)"
  else
    warn_msg "127.0.0.1 with rejection disabled: got CC=#{result.country_code}"
  end
rescue => e
  fail_msg "127.0.0.1 with rejection disabled raised: #{e.message}"
end
Trackdown.configuration.reject_private_ips = true

# IPv6
begin
  result = Trackdown.locate("2001:4860:4860::8888") # Google DNS IPv6
  if result.is_a?(Trackdown::LocationResult)
    pass "IPv6 lookup: CC=#{result.country_code}, city=#{result.city}"
  end
rescue => e
  warn_msg "IPv6 lookup failed: #{e.message}"
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "SUMMARY"

total_errors = errors.size + type_errors + concurrent_errors.size
if total_errors == 0
  puts "  \e[32m✓ ALL TESTS PASSED\e[0m"
else
  puts "  \e[31m✗ #{total_errors} ERRORS FOUND\e[0m"
end
puts
