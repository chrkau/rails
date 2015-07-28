load File.expand_path("../set_rails_env.rake", __FILE__)

module Capistrano
  class FileNotFound < StandardError
  end

  module DSL
    module Paths
      def rails_subpath
        rails_subpath = fetch(:rails_subpath)
        if !rails_subpath.nil? && !rails_subpath.end_with?('/')
          "#{rails_subpath}/"
        else
          ''
        end
      end

      def rails_release_path
        if rails_subpath
          release_path.join(rails_subpath)
        else
          release_path
        end
      end
    end
  end
end

namespace :deploy do
  before :starting, :set_shared_assets do
    set(:linked_dirs,
      (fetch(:linked_dirs) || []).push("#{rails_subpath}public/assets"))
  end

  desc 'Normalize asset timestamps'
  task :normalize_assets => [:set_rails_env] do
    on release_roles(fetch(:assets_roles)) do
      assets = fetch(:normalize_asset_timestamps)
      if assets
        within rails_release_path do
          execute :find, "#{assets} -exec touch -t #{asset_timestamp} {} ';'; true"
        end
      end
    end
  end

  desc 'Compile assets'
  task :compile_assets => [:set_rails_env] do
    invoke 'deploy:assets:precompile'
    invoke 'deploy:assets:backup_manifest'
  end

  # FIXME: it removes every asset it has just compiled
  desc 'Cleanup expired assets'
  task :cleanup_assets => [:set_rails_env] do
    on release_roles(fetch(:assets_roles)) do
      within rails_release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "assets:clean"
        end
      end
    end
  end

  desc 'Rollback assets'
  task :rollback_assets => [:set_rails_env] do
    begin
      invoke 'deploy:assets:restore_manifest'
    rescue Capistrano::FileNotFound
      invoke 'deploy:compile_assets'
    end
  end

  after 'deploy:updated', 'deploy:compile_assets'
  # NOTE: we don't want to remove assets we've just compiled
  # after 'deploy:updated', 'deploy:cleanup_assets'
  after 'deploy:updated', 'deploy:normalize_assets'
  after 'deploy:reverted', 'deploy:rollback_assets'

  namespace :assets do
    task :precompile do
      on release_roles(fetch(:assets_roles)) do
        within rails_release_path do
          with rails_env: fetch(:rails_env) do
            execute :rake, "assets:precompile"
          end
        end
      end
    end

    task :backup_manifest do
      on release_roles(fetch(:assets_roles)) do
        within rails_release_path do
          backup_path = release_path.join('assets_manifest_backup')

          execute :mkdir, '-p', backup_path
          execute :cp,
            detect_manifest_path,
            backup_path
        end
      end
    end

    task :restore_manifest do
      on release_roles(fetch(:assets_roles)) do
        within rails_release_path do
          target = detect_manifest_path
          source = rails_release_path.join('assets_manifest_backup', File.basename(target))
          if test "[[ -f #{source} && -f #{target} ]]"
            execute :cp, source, target
          else
            msg = 'Rails assets manifest file (or backup file) not found.'
            warn msg
            fail Capistrano::FileNotFound, msg
          end
        end
      end
    end

    def detect_manifest_path
      %w(
        .sprockets-manifest*
        manifest*.*
      ).each do |pattern|
        candidate = rails_release_path.join('public', fetch(:assets_prefix), pattern)
        return capture(:ls, candidate).strip if test(:ls, candidate)
      end
      msg = 'Rails assets manifest file not found.'
      warn msg
      fail Capistrano::FileNotFound, msg
    end
  end
end

namespace :load do
  task :defaults do
    set :assets_roles, fetch(:assets_roles, [:web])
    set :assets_prefix, fetch(:assets_prefix, 'assets')
    set :linked_dirs, fetch(:linked_dirs, []).push("public/#{fetch(:assets_prefix)}")
  end
end
