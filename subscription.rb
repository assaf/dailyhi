require "active_record"
require "openssl"
require "mail"
require "resolv"
require "flickr_fu"
require "tzinfo"
require "open-uri"
require "rss"
require "erb"

Mail.defaults do
  delivery_method :sendmail
end

env = ENV["RACK_ENV"] || "development"
HOSTNAME = env == "development" ? "localhost:3000" : "dailyhi.com"

config = YAML.load_file("#{File.dirname(__FILE__)}/config/database.yml")
ActiveRecord::Base.establish_connection config[env]
conn = ActiveRecord::Base.connection

# -- Hi's --

unless conn.table_exists?("his")
  conn.create_table "his" do |t|
    t.date    :date
    t.string  :fact
    t.string  :photo_url
    t.string  :flickr_url
    t.string  :flickr_name
  end
  conn.add_index :his, :date, :unique=>true
end

class Hi < ActiveRecord::Base
  class << self

    def fetch(date)
      unless hi = find_by_date(date)
        fact = fun_fact(date)
        photo = find_photo(date)
        hi = create(photo.merge(:date=>date, :fact=>fact))
      end
      hi
    end

    def fun_fact(date)
      if date.wday == 0
        # Chunk Norris fact
        week = date.strftime("%W").to_i || rand(52)
        File.read("chuck.txt").split("\n")[week]
      else
        facts = File.read("facts.txt").split("\n")
        facts[rand(facts.length)]
      end
    rescue
      "Alcohol beverages have all 13 minerals necessary for human life"
    end
    
    def find_photo(date)
      flickr = Flickr.new("#{File.dirname(__FILE__)}/config/flickr.yml")
      photos = flickr.photos.search(privacy_filter: 1, safe: 1, content_type: 1, license: "4,5,6",
                                    min_upload_date: (date - 1).to_time.to_i, sort: "interestingness-desc")
      photo = photos.find { |photo|
        large = photo.photo_size(:large)
        large && (800..1400).include?(large.width.to_i) && (600..1400).include?(large.height.to_i) }
      large = photo.photo_size(:large)
      { :photo_url=>large.source, :flickr_url=>photo.photopage_url, :flickr_name=>photo.owner_name }
    rescue
      { :photo_url=>"http://farm5.static.flickr.com/4119/4776902677_3b8193aedc_b.jpg",
        :flickr_url=>"http://www.flickr.com/photos/kenny_barker/4776902677/", :flickr_name=>"k.barker" }
    end

  end

  attr_accessible :date, :fact, :photo_url, :flickr_url, :flickr_name
end


# -- Subscriptions --

unless conn.table_exists?("subscriptions")
  conn.create_table "subscriptions" do |t|
    t.string  :code,     null: false, limit: 64
    t.string  :email,    null: false
    t.boolean :verified, null: false, default: false
    t.integer :timezone, limit: 1, default: -8
    t.timestamp
  end
  conn.add_index :subscriptions, :email
  conn.add_index :subscriptions, :code
  conn.add_index :subscriptions, :verified
  conn.add_index :subscriptions, :timezone
end


class Subscription < ActiveRecord::Base
  attr_accessible :email, :verified, :timezone
  attr_readonly :email, :code
  validates_presence_of :email
  validates_uniqueness_of :email, :code

  scope :verified, lambda { { conditions: { verified: true } } }

  before_validation do |record|
    record.email = Mail::Address.new(record.email).to_s.downcase
  end
  validate do |record|
    addr = Mail::Address.new(record.email) rescue nil
    if addr && addr.domain.present?
      mx = Resolv::DNS.open { |dns| dns.getresources(addr.domain, Resolv::DNS::Resource::IN::MX) }
      record.errors.add :email, :invalid if mx.empty?
    else
      record.errors.add :email, :invalid
    end
  end

  before_create do |record|
    record.verified = false
    record.code = OpenSSL::Random::random_bytes(16).unpack("H*").first
  end

  after_create do |record|
    Mail.deliver do
      from "The Daily Hi <hi@dailyhi.com>"
      to record.email
      subject "Please verify your email address"
      url = "http://#{HOSTNAME}/verify/#{record.code}"
      text_part do
        body <<-BODY
Before you can receive emails, we need to verify your email address.

Daily bliss, after you click this link:
  #{url}

        BODY
      end
    end
  end

  # Returns this subscription's "now" for immediate delivery.  For example:
  #   Subscription.deliver Subscription.find(1).my_now 
  def my_now
    utc = Time.now.utc
    now = Time.utc(utc.year, utc.month, utc.day, 6 - timezone)
  end

  class << self
    def deliver(utc = Time.now.utc)
      hour = utc.hour - 6 # 6 AM
      timezone = hour < 12 ? -hour : 24 - hour
      tz = TZInfo::Timezone.all_data_zones.find { |tz| tz.current_period.utc_offset.to_i == timezone * 60 * 60 }
      return unless tz
      time = tz.utc_to_local(utc)
      hi = Hi.fetch(time.to_date)

      subject = "Good morning, today is #{time.strftime("%A")}!"
      find_each conditions: { verified: true, timezone: timezone } do |subscription|
        html = email(subscription, time, hi)
        Mail.deliver do
          from "The Daily Hi <hi@dailyhi.com>"
          to subscription.email
          subject subject
          html_part do
            content_type "text/html"
            body html.force_encoding(Encoding::UTF_8)
          end
        end
      end
    end

    def email(subscription, time, hi)
      erb = ERB.new(File.read(File.dirname(__FILE__) + "/views/email.erb"))
      erb.result binding
    end
  end
end


if $0 == __FILE__
  begin
    Subscription.deliver
  rescue
    Mail.deliver do
      from "The Daily Hi <hi@dailyhi.com>"
      to "assaf@labnotes.org"
      subject $!.message
      text_part do
        content_type "text/plain"
        body $!.backtrace.join("\n")
      end
    end
  end
end
