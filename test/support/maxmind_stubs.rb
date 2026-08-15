# frozen_string_literal: true

require 'tmpdir'

module TestHelpers
  # Stand-ins for an open MaxMind database, so every MaxMind code path — including
  # database provenance — can be exercised without shipping a multi-megabyte
  # .mmdb fixture and without touching the network.
  module MaxmindStubs
    # An arbitrary but fixed "MaxMind built this database then" timestamp:
    # 2025-01-01 00:00:00 UTC.
    BUILD_EPOCH = 1_735_689_600

    FakeMetadata = Struct.new(:build_epoch)

    # Quacks like MaxMind::DB for the two things Trackdown asks of it.
    class FakeReader
      attr_reader :requested_ips

      def initialize(record: nil, build_epoch: nil, metadata: :derive, metadata_error: nil,
                     get_error: nil, get_delay: nil)
        @record = record
        @metadata = metadata == :derive ? FakeMetadata.new(build_epoch) : metadata
        @metadata_error = metadata_error
        @get_error = get_error
        @get_delay = get_delay
        @requested_ips = []
      end

      def get(ip)
        @requested_ips << ip
        sleep @get_delay if @get_delay
        raise @get_error if @get_error

        @record
      end

      def metadata
        raise @metadata_error if @metadata_error

        @metadata
      end

    end

    # Quacks like ConnectionPool.
    class FakeReaderPool
      attr_reader :reader

      def initialize(reader)
        @reader = reader
      end

      def with
        yield @reader
      end
    end

    # Run a block as if a MaxMind database were open at a real path on disk, so
    # digests and file-identity checks operate on genuine bytes.
    #
    #   with_maxmind_database(record: full_maxmind_record) do |path, reader|
    #     Trackdown::Providers::MaxmindProvider.locate('8.8.8.8')
    #   end
    def with_maxmind_database(record: full_maxmind_record, build_epoch: BUILD_EPOCH,
                              contents: 'a pretend GeoLite2-City database', metadata: :derive,
                              metadata_error: nil, get_error: nil, get_delay: nil)
      with_maxmind_database_file(contents) do |path|
        reader = FakeReader.new(record: record, build_epoch: build_epoch,
                                metadata: metadata, metadata_error: metadata_error,
                                get_error: get_error, get_delay: get_delay)

        Trackdown::Providers::MaxmindProvider.stub(:reader_pool, FakeReaderPool.new(reader)) do
          yield path, reader
        end
      end
    end

    # Just the file on disk, for tests that install their own reader.
    def with_maxmind_database_file(contents = 'a pretend GeoLite2-City database')
      Dir.mktmpdir('trackdown-test') do |directory|
        path = File.join(directory, 'GeoLite2-City.mmdb')
        File.binwrite(path, contents)
        Trackdown.configuration.database_path = path
        Trackdown::Providers::MaxmindProvider.reset_database!

        yield path
      end
    ensure
      Trackdown::Providers::MaxmindProvider.reset_database!
    end

    # Hand MaxmindProvider an already-open pool, the way a real first lookup would.
    def open_maxmind_pool(pool)
      Trackdown::Providers::MaxmindProvider.class_variable_set(:@@reader_pool, pool)
    end
  end
end
