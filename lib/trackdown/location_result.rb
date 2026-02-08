# frozen_string_literal: true

require 'countries'

module Trackdown
  class LocationResult
    attr_reader :country_code, :country_name, :city, :flag_emoji,
                :region, :region_code, :continent, :timezone, :latitude, :longitude,
                :postal_code, :metro_code

    def initialize(country_code, country_name, city, flag_emoji,
                   region: nil, region_code: nil, continent: nil,
                   timezone: nil, latitude: nil, longitude: nil,
                   postal_code: nil, metro_code: nil)
      @country_code = country_code
      @country_name = country_name
      @city = city
      @flag_emoji = flag_emoji
      @region = region
      @region_code = region_code
      @continent = continent
      @timezone = timezone
      @latitude = latitude
      @longitude = longitude
      @postal_code = postal_code
      @metro_code = metro_code
    end

    alias_method :country, :country_name
    alias_method :emoji, :flag_emoji
    alias_method :emoji_flag, :flag_emoji
    alias_method :country_flag, :flag_emoji

    def country_info
      return nil unless country_code
      ISO3166::Country.new(country_code)
    end

    def to_h
      {
        country_code: @country_code,
        country_name: @country_name,
        city: @city,
        flag_emoji: @flag_emoji,
        region: @region,
        region_code: @region_code,
        continent: @continent,
        timezone: @timezone,
        latitude: @latitude,
        longitude: @longitude,
        postal_code: @postal_code,
        metro_code: @metro_code,
        country_info: country_info&.data || {}
      }
    end
  end
end
