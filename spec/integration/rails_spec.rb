require 'spec_helper'

enable = false
begin
  require 'rails'
  require 'action_controller/railtie'
  require 'skylight/railtie'
  enable = true
rescue LoadError
  puts "[INFO] Skipping rails integration specs"
end

if enable

  class MyApp < Rails::Application
    config.secret_token = '095f674153982a9ce59914b561f4522a'
    config.active_support.deprecation = :stderr

    config.skylight.environments << 'development'

    config.logger = Logger.new(STDOUT)
    config.logger.level = Logger::DEBUG
  end

  class ::UsersController < ActionController::Base
    def index
      Skylight.instrument 'app.inside' do
        render text: "Hello"
        Skylight.instrument 'app.zomg' do
          # nothing
        end
      end
    end
  end

  describe 'Rails integration', :http do

    before :all do
      ENV['SK_AUTHENTICATION'] = 'lulz'
      ENV['SK_AGENT_INTERVAL'] = '1'
      ENV['SK_AGENT_STRATEGY'] = 'embedded'
      ENV['SK_REPORT_HOST']    = 'localhost'
      ENV['SK_REPORT_PORT']    = port.to_s
      ENV['SK_REPORT_SSL']     = false.to_s
      ENV['SK_REPORT_DEFLATE'] = false.to_s

      MyApp.initialize!

      MyApp.routes.draw do
        resources :users
      end
    end

    after :all do
      ENV['SK_AUTHENTICATION'] = nil
      ENV['SK_AGENT_INTERVAL'] = nil
      ENV['SK_AGENT_STRATEGY'] = nil
      ENV['SK_REPORT_HOST']    = nil
      ENV['SK_REPORT_PORT']    = nil
      ENV['SK_REPORT_SSL']     = nil
      ENV['SK_REPORT_DEFLATE'] = nil
      Skylight.stop!
    end

    it 'successfully calls into rails' do
      call MyApp, env('/users')

      server.wait
      batch = server.reports[0]
      batch.should have(1).endpoints
      endpoint = batch.endpoints[0]
      endpoint.name.should == "UsersController#index"
      endpoint.should have(1).traces
      trace = endpoint.traces[0]

      names = trace.spans.map { |s| s.event.category }

      names.length.should be >= 2
      names.should include('app.zomg')
      names.should include('app.inside')
      names[-1].should == 'app.rack.request'
    end

    def call(app, env)
      resp = app.call(env)
      consume(resp)
      nil
    end

    def env(path = '/', opts = {})
      Rack::MockRequest.env_for(path, {})
    end

    def consume(resp)
      resp[2].each { }
      resp[2].close
    end

  end
end