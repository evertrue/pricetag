require 'rubygems'
require 'bundler'

Bundler.require :default, ENV['PASSENGER_APP_ENV'].to_sym

set :environment, ENV['PASSENGER_APP_ENV'].to_sym
disable :run, :reload

server_script_path = File.join(
  File.dirname( File.expand_path(__FILE__) ), 'pricetag.rb'
)

require server_script_path

run Rack::URLMap.new '/' => Pricetag
