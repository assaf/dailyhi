require "sinatra"
require "subscription"
require "time"

ZONES = [[-11, "Midway Island", "Samoa" ],
       [-10, "Hawaii" ],
       [-9, "Alaska" ],
       [-8, "Pacific Time (US & Canada)", "Tijuana" ],
       [-7, "Mountain Time (US & Canada)", "Chihuahua", "Mazatlan" ],
       [-6, "Central Time (US & Canada)", "Mexico City", "Central America" ],
       [-5, "Eastern Time (US & Canada)", "Lima" ],
       [-4, "Atlantic Time (Canada)", "Santiago" ],
       [-3, "Buenos Aires", "Greenland" ],
       [-2, "Mid-Atlantic" ],
       [-1, "Cape Verde Is." ],
       [ 0, "London", "Casablanca" ],
       [ 1, "Paris", "West Central Africa" ],
       [ 2, "Cairo", "Helsinki" ],
       [ 3, "Moscow", "Baghdad" ],
       [ 4, "Abu Dhabi", "Tbilisi" ],
       [ 5, "Ekaterinburg", "Islamabad" ],
       [ 6, "Dhaka", "Novosibirsk" ],
       [ 7, "Bangkok", "Jakarta" ],
       [ 8, "Beijing", "Perth" ],
       [ 9, "Seoul", "Tokyo" ],
       [ 10, "Sydney", "Brisbane", "Guam" ],
       [ 11, "Magadan", "Solomon Is." ],
       [ 12, "Fiji", "Marshall Is." ]]


set :public, "#{File.dirname(__FILE__)}/public"

get '/' do
  @hi = Hi.fetch(Time.now)
  erb :index
end

post "/subscribe" do
  begin
    Subscription.create! email: params[:email], timezone: params[:timezone]
    redirect "/subscribed"
  rescue ActiveRecord::RecordInvalid=>ex
    erb :error, {}, error: ex.record.errors.full_messages.first
  rescue =>ex
    $stderr.puts ex
    $stderr.puts ex.backtrace
    erb :error, {}, error: ex.message
  end
end

get "/subscribed" do
  erb :subscribed
end

get "/verify/:code" do |code|
  Subscription.update_all({ verified: true }, { code: code })
  erb :verified
end

get "/unsubscribe/:code" do |code|
  Subscription.delete_all code: code
  erb :deleted
end

get "/timezone/:code" do |code|
  if subscription = Subscription.find_by_code(code)
    @code = subscription.code
    erb :timezone
  else
    not_found
  end
end

post "/timezone/:code" do |code|
  Subscription.update_all({ timezone: params[:timezone] }, { code: code })
  redirect "/timezoned"
end

get "/timezoned" do
  erb :timezoned
end

not_found do
  "Dude, you've been misdirected"
end
