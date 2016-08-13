require 'sinatra/base'
require 'json'
require 'base64'
require './tasks'
require './token'

class Application < ::Sinatra::Base
  configure :production, :development do
    enable :logging
  end

  disable :run

  post '/push' do
    unless request.content_type == 'application/json'
      halt 400
    end

    header_name = "HTTP_#{ENV['THEMIS_FINALS_AUTH_TOKEN_HEADER'].upcase.gsub('-', '_')}"
    auth_token = request.env[header_name]

    halt 401 unless ::Token.verify_master_token(auth_token)

    payload = nil

    begin
      request.body.rewind
      payload = ::JSON.parse request.body.read
    rescue => e
      puts e.to_s
      halt 400
    end

    Push.perform_async payload

    status 202
    body ''
  end

  post '/pull' do
    unless request.content_type == 'application/json'
      halt 400
    end

    header_name = "HTTP_#{ENV['THEMIS_FINALS_AUTH_TOKEN_HEADER'].upcase.gsub('-', '_')}"
    auth_token = request.env[header_name]

    halt 401 unless ::Token.verify_master_token(auth_token)

    payload = nil

    begin
      request.body.rewind
      payload = ::JSON.parse request.body.read
    rescue => e
      halt 400
    end

    Pull.perform_async payload

    status 202
    body ''
  end
end
