# frozen_string_literal: true

module Trackdown
  class LocationResult
    attr_reader :country_code, :country_name, :city, :flag_emoji

    def initialize(country_code, country_name, city, flag_emoji)
      @country_code = country_code
      @country_name = country_name
      @city = city
      @flag_emoji = flag_emoji
    end

    alias_method :country, :country_name
    alias_method :emoji, :flag_emoji
    alias_method :emoji_flag, :flag_emoji

    def to_h
      {
        country_code: @country_code,
        country_name: @country_name,
        city: @city,
        flag_emoji: @flag_emoji
      }
    end
  end
end
