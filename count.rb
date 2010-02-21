#!/usr/bin/env ruby
ENV["RACK_ENV"] = "production"
require "subscription"
verified = Subscription.verified
puts verified.all.map(&:email), "--------", verified.count
