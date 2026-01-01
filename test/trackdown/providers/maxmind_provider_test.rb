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
end
