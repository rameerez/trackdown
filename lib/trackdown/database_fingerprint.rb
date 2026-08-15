# frozen_string_literal: true

require 'digest'

module Trackdown
  # The identity of the MaxMind database file that answered a lookup.
  #
  # `build_epoch` comes straight from the database's own metadata, so it costs
  # nothing. The SHA-256 digest costs a full read of a ~70 MB file, so it is
  # computed the first time somebody asks for it and then reused for as long as
  # the file stays put — once per database version, never once per lookup.
  #
  # If the file changes underneath us the digest becomes `nil` rather than a
  # number that describes a file we are no longer reading.
  #
  # MaxMind documents the metadata section of the .mmdb format here:
  # https://maxmind.github.io/MaxMind-DB/
  class DatabaseFingerprint
    READ_CHUNK_BYTES = 1 << 20 # 1 MiB

    attr_reader :path, :build_epoch

    def initialize(path:, build_epoch: nil)
      @path = path
      @build_epoch = build_epoch
      @identity = file_identity
      @mutex = Mutex.new
    end

    # When MaxMind built this database.
    def built_at
      Time.at(@build_epoch).utc if @build_epoch.is_a?(Numeric)
    end

    # Has the file been replaced since we fingerprinted it?
    def changed?
      file_identity != @identity
    end

    # The digest of the database we read, or nil if we can't honestly compute one.
    def sha256
      return @sha256 if defined?(@sha256)

      @mutex.synchronize do
        @sha256 = compute_sha256 unless defined?(@sha256)
      end

      @sha256
    end

    private

    # Read the file whole, but hold only a chunk of it in memory at a time, and
    # confirm on both sides of the read that we digested a single stable file.
    def compute_sha256
      return nil if @identity.nil? || changed?

      digest = Digest::SHA256.new
      File.open(@path, 'rb') do |file|
        digest << file.read(READ_CHUNK_BYTES) until file.eof?
      end

      changed? ? nil : digest.hexdigest
    rescue SystemCallError, IOError
      nil
    end

    def file_identity
      stat = File.stat(@path)
      [stat.size, stat.mtime, stat.ino]
    rescue SystemCallError
      nil
    end
  end
end
