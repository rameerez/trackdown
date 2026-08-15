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
        say "\n  Option 1: Cloudflare (Header-Based)"
        say "    1. Ensure your app is behind Cloudflare"
        say "    2. Enable 'IP Geolocation' in Cloudflare dashboard (Network settings)"
        say "    3. Use: Trackdown.locate(request.remote_ip, request: request)"
        say "    4. Restrict direct-origin access before trusting CF-* headers"
        say "    Cloudflare origin security: https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/"
        say "    No API keys or database needed after CDN/origin setup."
        say "\n  Option 2: Amazon CloudFront (Header-Based)"
        say "    1. Forward CloudFront viewer-location headers and CloudFront-Viewer-Address"
        say "    2. Restrict direct-origin access before trusting CloudFront-* headers"
        say "    3. Use: Trackdown.locate(request.remote_ip, request: request)"
        say "    AWS headers: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location"
        say "    AWS origin security: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html"
        say "\n  Option 3: MaxMind (BYOK)"
        say "    1. Configure your MaxMind credentials in `config/initializers/trackdown.rb`"
        say "    2. Run 'Trackdown.update_database' to download the database"
        say "    3. Schedule TrackdownDatabaseRefreshJob to run weekly"
        say "\n  Option 4: Auto (Verified Edge + MaxMind Fallback)"
        say "    The default :auto mode uses one IP-corroborated CDN provider"
        say "    and falls back safely when no unique edge provider can be verified"
        say "\nEnjoy `trackdown`!", :green
      end

    end
  end
end
