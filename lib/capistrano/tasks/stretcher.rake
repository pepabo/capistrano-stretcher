# -*- coding: utf-8; mode: ruby -*-
require 'erb'
require 'yaml'

namespace :load do
  task :defaults do
    set :gzip_compress_level, "-9"
  end
end

namespace :stretcher do
  set :exclude_dirs, ["tmp"]

  def local_working_path_base
    @_local_working_path_base ||= fetch(:local_working_path_base, "/var/tmp/#{fetch :application}")
  end

  def local_repo_path
    "#{local_working_path_base}/repo"
  end

  def local_checkout_path
    "#{local_working_path_base}/checkout"
  end

  def local_build_path
    "#{local_working_path_base}/build"
  end

  def local_tarball_path
    "#{local_working_path_base}/tarballs"
  end

  def application_builder_roles
    roles(fetch(:application_builder_roles, [:build]))
  end

  def consul_roles
    roles(fetch(:consul_roles, [:consul]))
  end

  # upload to resource server with rsync
  def upload_resource(local_src_path, remote_dst_path)
    rsync_ssh_command = "ssh"
    rsync_ssh_command << " " + fetch(:rsync_ssh_option) if fetch(:rsync_ssh_option)
    rsync_ssh_user = fetch(:rsync_ssh_user) { capture(:whoami).strip }

    execute :rsync, "-ave", %Q("#{rsync_ssh_command}"),
            local_src_path,
            "#{rsync_ssh_user}@#{fetch(:rsync_host)}:#{remote_dst_path}"
  end

  task :mark_deploying do
    set :deploying, true
  end

  desc "Create a tarball that is set up for deploy"
  task :archive_project =>
    [:ensure_directories, :checkout_local,
     :create_tarball, :upload_tarball,
     :create_and_upload_manifest, :cleanup_dirs]

  task :ensure_directories do
    on application_builder_roles do
      execute :mkdir, '-p', local_repo_path, local_checkout_path, local_build_path, local_tarball_path
    end
  end

  task :checkout_local do
    on application_builder_roles do
      if test("[ -f #{local_repo_path}/HEAD ]")
        within local_repo_path do
          execute :git, :remote, :update
        end
      else
        execute :git, :clone, '--mirror', repo_url, local_repo_path
      end

      within local_repo_path do
        execute :mkdir, '-p', "#{local_checkout_path}/#{env.now}"
        execute :git, :archive, fetch(:branch), "| tar -x -C", "#{local_checkout_path}/#{env.now}"
        set :current_revision, capture(:git, 'rev-parse', fetch(:branch)).chomp

        execute :echo, fetch(:current_revision), "> #{local_checkout_path}/#{env.now}/REVISION"

        execute :rsync, "-av", "--delete",
          *fetch(:exclude_dirs, ["tmp"]).map{|d| ['--exclude', d].join(' ')},
          "#{local_checkout_path}/#{env.now}/", "#{local_build_path}/",
          "| pv -l -s $( find #{local_checkout_path}/#{env.now}/ -type f | wc -l ) >/dev/null"
      end
    end
  end

  task :create_tarball do
    on application_builder_roles do
      within local_build_path do
        compress_level = fetch(:gzip_compress_level, "-9")
        execute :mkdir, '-p', "#{local_tarball_path}/#{env.now}"
        execute :tar, '-cf', '-',
          "--exclude tmp", "--exclude spec", "./",
          "| pv -s $( du -sb ./ | awk '{print $1}' )",
          "| gzip #{compress_level} > #{local_tarball_path}/#{env.now}/#{fetch(:local_tarball_name)}"
      end
      within local_tarball_path do
        execute :rm, '-f', 'current'
        execute :ln, '-sf', env.now, 'current'
      end
    end
  end

  task :upload_tarball do
    on application_builder_roles do
      as 'root' do
        if fetch(:stretcher_src).start_with?("s3://")
          # upload to s3
          execute :aws, :s3, :cp, "#{local_tarball_path}/current/#{fetch(:local_tarball_name)}", fetch(:stretcher_src)
        else
          # upload to resource server with rsync
          upload_resource("#{local_tarball_path}/current/#{fetch(:local_tarball_name)}", fetch(:rsync_stretcher_src_path))
        end
      end
    end
  end

  task :create_and_upload_manifest do
    on application_builder_roles do
      as 'root' do
        failure_message = "Deploy failed at *$(hostname)* :fire:"
        checksum = capture("openssl sha256 #{local_tarball_path}/current/#{fetch(:local_tarball_name)} | gawk -F' ' '{print $2}'").chomp
        src = fetch(:stretcher_src)
        template = File.read(File.expand_path('../../templates/manifest.yml.erb', __FILE__))
        yaml = YAML.load(ERB.new(capture(:cat, "#{local_build_path}/#{fetch(:stretcher_hooks)}")).result(binding))
        fetch(:deploy_roles).split(',').each do |role|
          hooks = yaml[role]
          yml = ERB.new(template).result(binding)
          tempfile_path = Tempfile.open("manifest_#{role}") do |t|
            t.write yml
            t.path
          end
          upload! tempfile_path, "#{local_tarball_path}/current/manifest_#{role}_#{fetch(:stage)}.yml"

          if fetch(:manifest_path).start_with?("s3://")
            # upload to s3
            execute :aws, :s3, :cp, "#{local_tarball_path}/current/manifest_#{role}_#{fetch(:stage)}.yml", "#{fetch(:manifest_path)}/manifest_#{role}_#{fetch(:stage)}.yml"
          else
            # upload to resource server with rsync
            execute :chmod, "644", "#{local_tarball_path}/current/manifest_#{role}_#{fetch(:stage)}.yml"
            upload_resource("#{local_tarball_path}/current/manifest_#{role}_#{fetch(:stage)}.yml", "#{fetch(:rsync_manifest_path)}/manifest_#{role}_#{fetch(:stage)}.yml")
          end
        end
      end
    end
  end

  # refs https://github.com/capistrano/capistrano/blob/master/lib/capistrano/tasks/deploy.rake#L138
  task :cleanup_dirs do
    on application_builder_roles do
      releases = capture(:ls, '-tr', "#{local_tarball_path}", "| grep -v current").split

      if releases.count >= fetch(:keep_releases)
        info t(:keeping_releases, host: host.to_s, keep_releases: fetch(:keep_releases), releases: releases.count)
        directories = (releases - releases.last(fetch(:keep_releases)))
        unless directories.empty?
          directories_str = directories.map do |release|
            "#{local_tarball_path}/#{release} #{local_checkout_path}/#{release}"
          end.join(" ")
          execute :rm, '-rf', directories_str
        else
          info t(:no_old_releases, host: host.to_s, keep_releases: fetch(:keep_releases))
        end
      end
    end
  end

  desc "Kick the stretcher's deploy event via Consul"
  task :kick_stretcher do
    fetch(:deploy_roles).split(',').each do |target_role|
      on consul_roles do
        opts = ["-name deploy_#{target_role}_#{fetch(:stage)}"]
        opts << "-node #{ENV['TARGET_HOSTS']}" if ENV['TARGET_HOSTS']
        opts << "#{fetch(:manifest_path)}/manifest_#{target_role}_#{fetch(:stage)}.yml"
        execute :consul, :event, *opts
      end
    end
  end

  desc 'Deploy via Stretcher'
  task :deploy => ["stretcher:mark_deploying", "stretcher:archive_project", "stretcher:kick_stretcher"]
end
