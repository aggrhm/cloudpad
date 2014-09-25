# Getting Started

This guide will step you through setting up a new deployment application with Cloudpad.

## Installing

Create a directory and add a Gemfile:

```sh
$ mkdir app-deploy
$ cd app-deploy
$ touch Gemfile
```

Add this line to your application's Gemfile:

```ruby
source 'http://rubygems.org'
gem 'cloudpad', :github => 'agquick/cloudpad'
gem 'cloudpad-starter', :github => 'agquick/cloudpad-starter' # if you want cloudpad base dockerfiles, etc. This is optional.
```

And then execute:

```sh
$ bundle install
$ bundle exec cap install
```

Update your Capfile:

```ruby
# Capfile

require 'capistrano/setup'
# require 'capistrano/deploy' # comment this line out

require 'cloudpad'

# any extensions go here, for example cloudpad/starter
require 'cloudpad/starter'
```

Delete everything in `config/deploy.rb`

```ruby
# config/deploy.rb
# This is your configuration file. Let's make it empty for now...
```

## Directory Structure

More coming soon...


## Installing Extension Files

If you are using any extensions, you can run the relevant commands now. For example, this will install the starter files:

```sh
$ bundle exec cap production starter:install:all
```

Now you are ready to:

1. Build your configuration file (see Configuration documentation)
2. Provision your hosts (see Usage documentation)
3. Build and deploy your images and containers (see Usage documentation)

