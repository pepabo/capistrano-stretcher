# Capistrano::Stretcher

capistrano task for stretcher.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'capistrano-stretcher'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-stretcher

## Requirements

capistrano-stretcher requires target server for building to application assets. This server should be installed the following packages:

 * git
 * rsync
 * tar
 * gzip
 * awk
 * openssl
 * aws-cli
 * consul

target server builds assets, uploads assets to AWS S3 and invokes `consul event` automatically. So target server can access AWS s3 via aws-cli and join your deployment consul cluster.

## Usage

You need to add `require "capistrano/stretcher"` to Capfile and add `config/deploy.rb` following variables:

```ruby
role :build, ['your-target-server.lan'], :no_release => true
set :application, 'your-application'
set :deploy_to, '/var/www'
set :deploy_roles, 'www,batch'
set :stretcher_hooks, 'config/stretcher.yml.erb'
set :local_tarball_name, 'rails-applicaiton.tar.gz'
set :stretcher_src, "s3://your-deployment-bucket/assets/rails-application-#{env.now}.tgz"
set :manifest_path, "s3://your-deployment-bucket/manifests/"
```

and write hooks for stretcher to `config/stretcher.yml.erb`

```yaml
default: &default
  pre:
    -
  success:
    -
  failure:
    - cat >> /tmp/failure
www:
  <<: *default
  post:
    - ln -nfs <%= fetch(:deploy_to) %>/shared/data <%= fetch(:deploy_to) %>/current/data
    - sudo systemctl reload unicorn
batch:
  <<: *default
  post:
    - ln -nfs <%= fetch(:deploy_to) %>/shared/data <%= fetch(:deploy_to) %>/current/data
```

above hooks is extracted to manifest.yml for stretcher. If you have "www,batch" roles and stages named staging and production, capistrano-stretcher extract to following yaml from configuration.

 * `manifest_www_staging.yml`
 * `manifest_batch_staging.yml`

and invoke

 * `consul event -name deploy_www_staging s3://.../manifest_www.yml`
 * `consul event -name deploy_batch_staging s3://.../manifest_batch.yml`

with `cap staging stretcher:deploy` command on target server. When it's invoked with `cap production stretcher:deploy`, capistrano-stretcher replace suffix `staging` to `production`.

## Related Projects

 * [capistrano-stretcher-rails](https://github.com/pepabo/capistrano-stretcher-rails)
 * [capistrano-stretcher-npm](https://github.com/pepabo/capistrano-stretcher-npm)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/pepabo/capistrano-stretcher.

## LICENSE

The MIT License (MIT)

Copyright (c) 2015- GMO Pepabo, Inc.
