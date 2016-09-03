require 'sinatra/base'
require 'json'
require 'base64'
require './tasks'
require './utils'
require 'rack'

class Application < ::Sinatra::Base
  configure :production, :development do
    enable :logging
  end

  disable :run

  class AuthTokenChecker
    def initialize(app)
      @app = app
      @header_name = "HTTP_#{ENV['THEMIS_FINALS_AUTH_TOKEN_HEADER'].upcase.gsub('-', '_')}"
    end

    def call(env)
      token = env[@header_name]
      if verify_master_token token
        @app.call env
      else
        Rack::Response.new([], 401, {}).finish
      end
    end
  end

  class JSONBodyParser
    def initialize(app)
      @app = app
    end

    def call(env)
      req = Rack::Request.new(env)
      logger = env['rack.logger']
      proceed = true
      if req.request_method == 'POST'
        if req.content_type == 'application/json'
          begin
            req.body.rewind
            payload = ::JSON.parse req.body.read
            logger.info(payload)
            env['json_body'] = payload
          rescue e
            logger.error e.message
            e.backtrace.each { |line| logger.error line }
          end
        else
          proceed = false
        end
      end

      if proceed
        @app.call env
      else
        Rack::Response.new([], 400, {}).finish
      end
    end
  end

  use AuthTokenChecker
  use JSONBodyParser

  post '/push' do
    Push.perform_async request.env['json_body']
    status 202
    body ''
  end

  post '/pull' do
    Pull.perform_async request.env['json_body']
    status 202
    body ''
  end
end
