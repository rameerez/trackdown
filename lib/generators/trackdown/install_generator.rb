module Trackdown
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def create_initializer
        template 'trackdown.rb', 'config/initializers/trackdown.rb'
      end

      def create_database_refresh_job
        template 'trackdown_database_refresh_job.rb', 'app/jobs/trackdown_database_refresh_job.rb'
      end

      def add_mmdb_to_gitignore
        if File.exist?('.gitignore')
          append_to_file '.gitignore', "\n\n# Trackdown\n*.mmdb"
        else
          create_file '.gitignore', "# Trackdown\n*.mmdb"
        end
      end

      def display_post_install_message
        say "\tThe `trackdown` gem has been successfully installed!", :green
        say "\nTo complete the setup:"
        say "  1. Configure your MaxMind credentials in `config/initializers/trackdown.rb`"
        say "  2. Run 'Trackdown.update_database' to get a fresh MaxMind IP database."
        say "  3. Make sure you configure your queueing system to run the TrackdownDatabaseRefreshJob regularly so the IP database is updated regularly."
        say "\nEnjoy `trackdown`!", :green
      end

    end
  end
end
