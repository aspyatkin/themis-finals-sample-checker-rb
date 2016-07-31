require 'sinatra/base'
require 'json'
require 'base64'
require './tasks'

class Application < ::Sinatra::Base
  configure :production, :development do
    enable :logging
  end

  disable :run

  post '/push' do
    unless request.content_type == 'application/json'
      halt 400
    end

    payload = nil

    begin
      request.body.rewind
      payload = ::JSON.parse request.body.read
    rescue => e
      puts e.to_s
      halt 400
    end

    Push.perform_async payload

    status 201
    body ''
  end

  post '/pull' do
    unless request.content_type == 'application/json'
      halt 400
    end

    payload = nil

    begin
      request.body.rewind
      payload = ::JSON.parse request.body.read
    rescue => e
      halt 400
    end

    Pull.perform_async payload

    status 201
    body ''
  end
end
