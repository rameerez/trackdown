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
        say "\nChoose your setup path:"
        say "\n  Option 1: Cloudflare (Zero Config - Recommended)"
        say "    1. Ensure your app is behind Cloudflare"
        say "    2. Enable 'IP Geolocation' in Cloudflare dashboard (Network settings)"
        say "    3. Use: Trackdown.locate(request.remote_ip, request: request)"
        say "    That's it! No API keys, no database needed."
        say "\n  Option 2: MaxMind (BYOK)"
        say "    1. Configure your MaxMind credentials in `config/initializers/trackdown.rb`"
        say "    2. Run 'Trackdown.update_database' to download the database"
        say "    3. Schedule TrackdownDatabaseRefreshJob to run weekly"
        say "\n  Option 3: Auto (Best of Both)"
        say "    The default :auto mode tries Cloudflare first, falls back to MaxMind"
        say "\nEnjoy `trackdown`!", :green
      end

    end
  end
end
