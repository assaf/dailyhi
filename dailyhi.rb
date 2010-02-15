require "sinatra/base"
require "subscription"


class DailyHi < Sinatra::Default
  set :public, "#{__FILE__}/../public"

  get '/' do
    erb :index
  end

  post "/subscribe" do
    begin
      Subscription.create! email: params[:email]
      redirect "/subscribed"
    rescue
      error = ($!.record.errors.full_messages.first rescue $!.message)
      erb :error, {}, error: error
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

  not_found do
    "Dude, you've been misdirected"
  end
end
