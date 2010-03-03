#!/usr/bin/env ruby
ENV["RACK_ENV"] = "production"
require "bundler"
Bundler.setup
require "subscription"
verified = Subscription.verified
puts verified.all.map(&:email), "--------", verified.count
