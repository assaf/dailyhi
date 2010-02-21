require "active_record"
require "openssl"
require "mail"
require "resolv"
require "flickr_fu"

Mail.defaults do
  delivery_method :sendmail
end

env = ENV["RACK_ENV"] || "development"
HOSTNAME = env == "development" ? "localhost:7887" : "dailyhi.labnotes.org"

config = YAML.load_file("#{File.dirname(__FILE__)}/config/database.yml")
ActiveRecord::Base.establish_connection config[env]
conn = ActiveRecord::Base.connection
unless conn.table_exists?("subscriptions")
  conn.create_table "subscriptions" do |t|
    t.string  :code,     null: false, limit: 64
    t.string  :email,    null: false
    t.boolean :verified, null: false, default: false
    t.timestamp
  end
  conn.add_index :subscriptions, :email
  conn.add_index :subscriptions, :code
  conn.add_index :subscriptions, :verified
end


class Subscription < ActiveRecord::Base
  attr_accessible :email, :verified
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
    mail = Mail::Message.new(from: "dailyhi@labnotes.org", to: record.email, subject: "Please verify your email address")
    url = "http://#{HOSTNAME}/verify/#{record.code}"
    mail.text_part = Mail::Part.new(body: <<-BODY)
Before you can receive emails, we need to verify your email address.

Daily bliss, after you click this link:
  #{url}

    BODY
    mail.deliver
  end

  class << self
    def photo(day)
      flickr = Flickr.new("#{File.dirname(__FILE__)}/config/flickr.yml")
      photos = flickr.photos.search(tags: day, privacy_filter: 1, safe: 1, content_type: 1, license: "4,5,6",
                                    min_upload_date: (Date.today - 7).to_time.to_i, sort: "interestingness-desc")
      photo = photos.find { |photo|
        large = photo.photo_size(:large)
        large && (800..1400).include?(large.width.to_i) && (600..1400).include?(large.height.to_i) }
    end

    def daily(day = Time.now.strftime("%A"))
      if photo = photo(day)
        large = photo.photo_size(:large)
        image = <<-HTML
<div><a href="#{large.url}"><img src="#{large.source}" width="#{large.width} height="#{large.height}"></a></div>
<h4>Photo by <a href="#{photo.photopage_url}">#{CGI.escapeHTML photo.owner_name}</a></h4>
        HTML
      end
      subject = "Good morning, today is #{day}!"
      find_each conditions: { verified: true } do |subscription|
        mail = Mail::Message.new(from: "dailyhi@labnotes.org", to: subscription.email, subject: subject)
        url = "http://#{HOSTNAME}/unsubscribe/#{subscription.code}"
      mail.html_part = Mail::Part.new(content_type: "text/html", body: <<-HTML)
<h2>A lovely #{day} to you!</h2>
#{image}
<hr>
<p>To unsubscribe: <a href="#{url}">#{url}</a></p>
      HTML
        mail.deliver
      end
    end
  end
end

Subscription.daily if $0 == __FILE__
