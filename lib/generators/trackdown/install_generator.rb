module Trackdown
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def create_initializer
        template 'trackdown.rb', 'config/initializers/trackdown.rb'
      end

      def create_database_update_task
        template 'update_maxmind_database.rake', 'lib/tasks/update_maxmind_database.rake'
      end

      def setup_whenever
        if File.exist?('config/schedule.rb')
          append_to_file 'config/schedule.rb' do
            "\n# Update MaxMind IP geolocation database\nevery 1.week do\n  rake \"trackdown:update_database\"\nend\n"
          end
        else
          create_file 'config/schedule.rb' do
            "# Use this file to easily define all of your cron jobs.\n#\n# Learn more: http://github.com/javan/whenever\n\n# Update MaxMind IP geolocation database\nevery 1.week do\n  rake \"trackdown:update_database\"\nend\n"
          end
        end
      end

      def display_post_install_message
        say "\tThe `trackdown` gem has been successfully installed!", :green
        say "\nTo complete the setup:"
        say "  1. Configure your MaxMind credentials in `config/initializers/trackdown.rb`"
        say "  2. Run 'Trackdown.update_database' to get a fresh MaxMind IP database."
        say "  3. Make sure you have a functional `whenever` gem setup that can run cron jobs properly so the IP database is updated regularly."
        say "\nEnjoy `trackdown`!", :green
      end

    end
  end
end
