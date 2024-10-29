class TrackdownDatabaseRefreshJob < ApplicationJob
  queue_as :default

  def perform(*args)
    Trackdown.update_database
  end
end
