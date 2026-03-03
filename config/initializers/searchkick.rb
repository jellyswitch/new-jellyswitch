if Rails.env.test?
  Rails.application.config.middleware.insert_before 0, Class.new {
    def initialize(app)
      @app = app
    end
    def call(env)
      Searchkick.callbacks(false) { @app.call(env) }
    end
  }
end
