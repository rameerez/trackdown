# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class DatabaseFingerprintTest < Minitest::Test
  CONTENTS = 'a pretend GeoLite2-City database'

  def with_database_file(contents = CONTENTS)
    Dir.mktmpdir('trackdown-fingerprint') do |directory|
      path = File.join(directory, 'GeoLite2-City.mmdb')
      File.binwrite(path, contents)
      yield path
    end
  end

  def fingerprint_for(path, build_epoch: 1_735_689_600)
    Trackdown::DatabaseFingerprint.new(path: path, build_epoch: build_epoch)
  end

  def test_remembers_the_path
    with_database_file do |path|
      assert_equal path, fingerprint_for(path).path
    end
  end

  def test_exposes_the_build_epoch_it_was_given
    with_database_file do |path|
      assert_equal 1_735_689_600, fingerprint_for(path).build_epoch
    end
  end

  def test_built_at_reads_the_build_epoch_as_a_utc_time
    with_database_file do |path|
      assert_equal Time.utc(2025, 1, 1), fingerprint_for(path).built_at
      assert_equal 'UTC', fingerprint_for(path).built_at.zone
    end
  end

  def test_built_at_is_nil_without_a_build_epoch
    with_database_file do |path|
      assert_nil fingerprint_for(path, build_epoch: nil).built_at
    end
  end

  def test_digests_the_file_it_fingerprinted
    with_database_file do |path|
      assert_equal Digest::SHA256.hexdigest(CONTENTS), fingerprint_for(path).sha256
    end
  end

  def test_digests_an_empty_file
    with_database_file('') do |path|
      assert_equal Digest::SHA256.hexdigest(''), fingerprint_for(path).sha256
    end
  end

  def test_digests_a_file_larger_than_one_read_chunk
    contents = 'x' * (Trackdown::DatabaseFingerprint::READ_CHUNK_BYTES + 1024)

    with_database_file(contents) do |path|
      assert_equal Digest::SHA256.hexdigest(contents), fingerprint_for(path).sha256
    end
  end

  def test_digests_binary_content_faithfully
    contents = (0..255).map(&:chr).join.b * 8

    with_database_file(contents) do |path|
      assert_equal Digest::SHA256.hexdigest(contents), fingerprint_for(path).sha256
    end
  end

  def test_reads_the_file_once_and_reuses_the_digest
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      expected = Digest::SHA256.hexdigest(CONTENTS)

      assert_equal expected, fingerprint.sha256

      File.delete(path)

      assert_equal expected, fingerprint.sha256, 'the digest should be remembered, not recomputed'
    end
  end

  def test_reports_a_file_that_has_not_changed
    with_database_file do |path|
      refute_predicate fingerprint_for(path), :changed?
    end
  end

  def test_reports_a_file_whose_contents_were_replaced
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      File.binwrite(path, 'a different database entirely')

      assert_predicate fingerprint, :changed?
    end
  end

  def test_reports_a_file_that_was_swapped_for_another
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      replacement = "#{path}.new"
      File.binwrite(replacement, CONTENTS)
      File.rename(replacement, path)

      assert_predicate fingerprint, :changed?
    end
  end

  def test_reports_a_file_that_disappeared
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      File.delete(path)

      assert_predicate fingerprint, :changed?
    end
  end

  def test_refuses_to_digest_a_file_that_changed_underneath_it
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      File.binwrite(path, 'a different database entirely')

      assert_nil fingerprint.sha256, 'we must not describe a file we are no longer reading'
    end
  end

  def test_adding_reader_metadata_preserves_the_identity_captured_before_the_reader_opened
    with_database_file('database generation A') do |path|
      fingerprint_before_reader_open = Trackdown::DatabaseFingerprint.new(path: path)
      replacement = "#{path}.new"
      File.binwrite(replacement, 'database generation B')
      File.rename(replacement, path)

      reader_bound_fingerprint = fingerprint_before_reader_open.with_build_epoch(123)

      assert_equal 123, reader_bound_fingerprint.build_epoch
      assert_predicate reader_bound_fingerprint, :changed?
      assert_nil reader_bound_fingerprint.sha256,
                 'metadata from a reader opened after replacement must not make the old identity digest the new path'
    end
  end

  def test_refuses_to_digest_a_file_that_disappeared
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      File.delete(path)

      assert_nil fingerprint.sha256
    end
  end

  def test_refuses_to_digest_a_file_that_never_existed
    fingerprint = Trackdown::DatabaseFingerprint.new(path: '/nonexistent/GeoLite2-City.mmdb')

    assert_nil fingerprint.sha256
    assert_nil fingerprint.build_epoch
  end

  def test_survives_an_unreadable_file
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      File.chmod(0o000, path)

      # Root can read anything, so only assert the contract we can actually test.
      skip 'running as a user that can read any file' if File.readable?(path)

      assert_nil fingerprint.sha256
    ensure
      File.chmod(0o600, path)
    end
  end

  def test_remembers_a_failed_digest_rather_than_retrying_forever
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      File.delete(path)

      assert_nil fingerprint.sha256

      File.binwrite(path, CONTENTS)

      assert_nil fingerprint.sha256, 'a fingerprint describes one file, once'
    end
  end

  def test_computes_the_digest_only_once_across_threads
    with_database_file do |path|
      fingerprint = fingerprint_for(path)
      digests = Array.new(8) { Thread.new { fingerprint.sha256 } }.map(&:value)

      assert_equal [Digest::SHA256.hexdigest(CONTENTS)] * 8, digests
    end
  end
end
