require "active_record"
require "openssl"
require "mail"
require "resolv"
require "flickr_fu"
require "tzinfo"

Mail.defaults do
  delivery_method :sendmail
end

env = ENV["RACK_ENV"] || "development"
HOSTNAME = env == "development" ? "localhost:3000" : "dailyhi.labnotes.org"

config = YAML.load_file("#{File.dirname(__FILE__)}/config/database.yml")
ActiveRecord::Base.establish_connection config[env]
conn = ActiveRecord::Base.connection
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

  named_scope :verified, lambda { { conditions: { verified: true } } }

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
    mail = Mail::Message.new(from: "The Daily Hi <dailyhi@labnotes.org>", to: record.email, subject: "Please verify your email address")
    url = "http://#{HOSTNAME}/verify/#{record.code}"
    mail.text_part = Mail::Part.new(body: <<-BODY)
Before you can receive emails, we need to verify your email address.

Daily bliss, after you click this link:
  #{url}

    BODY
    mail.deliver
  end

  class << self
    def find_photo
      flickr = Flickr.new("#{File.dirname(__FILE__)}/config/flickr.yml")
      photos = flickr.photos.search(privacy_filter: 1, safe: 1, content_type: 1, license: "4,5,6",
                                    min_upload_date: (Date.today - 7).to_time.to_i, sort: "interestingness-desc")
      photo = photos.find { |photo|
        large = photo.photo_size(:large)
        large && (800..1400).include?(large.width.to_i) && (600..1400).include?(large.height.to_i) }
    end

    def image_html
      return @image_html if @image_html
      if photo = find_photo
        large = photo.photo_size(:large)
        @image_html = <<-HTML
<div><a href="#{large.url}"><img src="#{large.source}" width="480px"></a></div>
<h4>Photo by <a href="#{photo.photopage_url}">#{CGI.escapeHTML photo.owner_name}</a></h4>
        HTML
      end
    end

    def deliver(utc = Time.now.utc)
      hour = utc.hour - 6 # 6 AM
      timezone = hour < 12 ? -hour : 24 - hour
      tz = TZInfo::Timezone.all_data_zones.find { |tz| tz.current_period.utc_offset.to_i == timezone * 60 * 60 }
      return unless tz
      day = tz.strftime("%A", utc)
      subject = "Good morning, today is #{day}!"
      find_each conditions: { verified: true, timezone: timezone } do |subscription|
        mail = Mail::Message.new(from: "The Daily Hi <dailyhi@labnotes.org>", to: subscription.email, subject: subject)
        url = "http://#{HOSTNAME}/unsubscribe/#{subscription.code}"
        mail.html_part = Mail::Part.new(content_type: "text/html", body: <<-HTML)
<h2>A lovely #{day} to you!</h2>
<p><b>Important</b>: Not happy with your timezone? <a href="http://#{HOSTNAME}/timezone/#{subscription.code}">Go here to change it</a>.</p>
#{image_html}
<hr>
<p>To unsubscribe: <a href="#{url}">#{url}</a></p>
        HTML
        mail.deliver
      end
    end

  end
end

Subscription.deliver if $0 == __FILE__
