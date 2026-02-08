# frozen_string_literal: true

require "test_helper"

class MaxmindProviderTest < Minitest::Test
  def test_available_returns_false_when_database_missing
    Trackdown.configuration.database_path = '/nonexistent/path.mmdb'

    refute Trackdown::Providers::MaxmindProvider.available?
  end

  def test_available_returns_true_when_gem_and_database_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      # MaxMind gem is loaded in test environment
      assert Trackdown::Providers::MaxmindProvider.available?
    end
  end

  def test_locate_raises_error_without_database
    Trackdown.configuration.database_path = '/nonexistent/path.mmdb'

    error = assert_raises(Trackdown::Error) do
      Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')
    end

    assert_match(/MaxMind database not found/, error.message)
  end

  def test_locate_extracts_country_code_from_record
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'US',
        'names' => {'en' => 'United States'}
      },
      'city' => {
        'names' => {'en' => 'Mountain View'}
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'US', result.country_code
      end
    end
  end

  def test_locate_extracts_country_name_from_record
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'GB',
        'names' => {'en' => 'United Kingdom'}
      },
      'city' => {
        'names' => {'en' => 'London'}
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('1.2.3.4')

        assert_equal 'United Kingdom', result.country_name
      end
    end
  end

  def test_locate_extracts_city_from_record
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'FR',
        'names' => {'en' => 'France'}
      },
      'city' => {
        'names' => {'en' => 'Paris'}
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('5.6.7.8')

        assert_equal 'Paris', result.city
      end
    end
  end

  def test_locate_returns_unknown_for_nil_record
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, nil do
        result = Trackdown::Providers::MaxmindProvider.locate('127.0.0.1')

        assert_nil result.country_code
        assert_equal 'Unknown', result.country_name
        assert_equal 'Unknown', result.city
        assert_equal '🏳️', result.flag_emoji
      end
    end
  end

  def test_locate_returns_location_result
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'US',
        'names' => {'en' => 'United States'}
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_instance_of Trackdown::LocationResult, result
      end
    end
  end

  def test_extract_country_name_prefers_english
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'DE',
        'names' => {
          'de' => 'Deutschland',
          'en' => 'Germany',
          'fr' => 'Allemagne'
        }
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('1.2.3.4')

        assert_equal 'Germany', result.country_name
      end
    end
  end

  def test_extract_country_name_falls_back_to_any_language
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'DE',
        'names' => {
          'de' => 'Deutschland'
          # No English name
        }
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('1.2.3.4')

        assert_equal 'Deutschland', result.country_name
      end
    end
  end

  def test_extract_city_prefers_english
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'FR',
        'names' => {'en' => 'France'}
      },
      'city' => {
        'names' => {
          'fr' => 'Lyon',
          'en' => 'Lyon'
        }
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('1.2.3.4')

        assert_equal 'Lyon', result.city
      end
    end
  end

  def test_handles_missing_city_data
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'US',
        'names' => {'en' => 'United States'}
      }
      # No city data
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'Unknown', result.city
      end
    end
  end

  def test_handles_empty_country_names
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    mock_record = {
      'country' => {
        'iso_code' => 'XX',
        'names' => {}
      }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, mock_record do
        result = Trackdown::Providers::MaxmindProvider.locate('1.2.3.4')

        assert_equal 'Unknown', result.country_name
      end
    end
  end

  # === New fields: region, region_code, continent, timezone, latitude, longitude ===

  def test_locate_extracts_region_with_english_name
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'California', result.region
      end
    end
  end

  def test_locate_extracts_region_falls_back_without_english_name
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record['subdivisions'][0]['names'] = { 'de' => 'Kalifornien' }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'Kalifornien', result.region
      end
    end
  end

  def test_locate_extracts_region_nil_when_no_subdivisions
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record.delete('subdivisions')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.region
      end
    end
  end

  def test_locate_extracts_region_code_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'CA', result.region_code
      end
    end
  end

  def test_locate_extracts_region_code_absent
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record.delete('subdivisions')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.region_code
      end
    end
  end

  def test_locate_extracts_continent_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'NA', result.continent
      end
    end
  end

  def test_locate_extracts_continent_absent
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record.delete('continent')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.continent
      end
    end
  end

  def test_locate_extracts_timezone_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'America/Los_Angeles', result.timezone
      end
    end
  end

  def test_locate_extracts_timezone_absent
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record.delete('location')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.timezone
      end
    end
  end

  def test_locate_extracts_latitude_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_in_delta 37.7749, result.latitude
      end
    end
  end

  def test_locate_extracts_longitude_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_in_delta(-122.4194, result.longitude)
      end
    end
  end

  def test_locate_latitude_absent_when_no_location
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record.delete('location')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.latitude
        assert_nil result.longitude
      end
    end
  end

  def test_locate_latitude_longitude_zero_values
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record['location']['latitude'] = 0.0
    record['location']['longitude'] = 0.0

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_in_delta 0.0, result.latitude
        assert_in_delta 0.0, result.longitude
      end
    end
  end

  def test_locate_multiple_subdivisions_extracts_first
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record['subdivisions'] = [
      { 'iso_code' => 'CA', 'names' => { 'en' => 'California' } },
      { 'iso_code' => 'LA', 'names' => { 'en' => 'Los Angeles County' } }
    ]

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'California', result.region
        assert_equal 'CA', result.region_code
      end
    end
  end

  def test_locate_missing_subdivisions_key
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = {
      'country' => { 'iso_code' => 'US', 'names' => { 'en' => 'United States' } },
      'city' => { 'names' => { 'en' => 'San Francisco' } }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.region
        assert_nil result.region_code
      end
    end
  end

  def test_locate_missing_location_key
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = {
      'country' => { 'iso_code' => 'US', 'names' => { 'en' => 'United States' } },
      'city' => { 'names' => { 'en' => 'San Francisco' } }
    }

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.timezone
        assert_nil result.latitude
        assert_nil result.longitude
      end
    end
  end

  def test_locate_empty_record_returns_unknown_with_nil_new_fields
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, nil do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.region
        assert_nil result.region_code
        assert_nil result.continent
        assert_nil result.timezone
        assert_nil result.latitude
        assert_nil result.longitude
        assert_nil result.postal_code
        assert_nil result.metro_code
      end
    end
  end

  def test_locate_full_record_populates_all_new_fields
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal 'US', result.country_code
        assert_equal 'United States', result.country_name
        assert_equal 'San Francisco', result.city
        assert_equal 'California', result.region
        assert_equal 'CA', result.region_code
        assert_equal 'NA', result.continent
        assert_equal 'America/Los_Angeles', result.timezone
        assert_in_delta 37.7749, result.latitude
        assert_in_delta(-122.4194, result.longitude)
        assert_equal '94107', result.postal_code
        assert_equal '807', result.metro_code
      end
    end
  end

  def test_locate_empty_subdivisions_array
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record['subdivisions'] = []

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.region
        assert_nil result.region_code
      end
    end
  end

  def test_locate_location_without_timezone
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record['location'].delete('time_zone')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.timezone
        # latitude and longitude should still be present
        assert_in_delta 37.7749, result.latitude
      end
    end
  end

  # === postal_code and metro_code ===

  def test_locate_extracts_postal_code_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal '94107', result.postal_code
      end
    end
  end

  def test_locate_extracts_metro_code_present
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, full_maxmind_record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal '807', result.metro_code
      end
    end
  end

  def test_locate_postal_code_absent
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record.delete('postal')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.postal_code
      end
    end
  end

  def test_locate_metro_code_absent
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record['location'].delete('metro_code')

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.metro_code
      end
    end
  end

  def test_locate_metro_code_converts_integer_to_string
    Trackdown.configuration.database_path = '/fake/path.mmdb'
    record = full_maxmind_record
    record['location']['metro_code'] = 501

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, record do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_equal '501', result.metro_code
      end
    end
  end

  def test_locate_nil_record_has_nil_postal_and_metro
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::MaxmindProvider.stub :fetch_record, nil do
        result = Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')

        assert_nil result.postal_code
        assert_nil result.metro_code
      end
    end
  end
end
