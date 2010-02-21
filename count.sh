#!/usr/bin/sh
RACK_ENV=production bundle exec ruby -rsubscription -e "v = Subscription.verified; puts v.all.map(&:email), v.count"
