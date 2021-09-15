web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -q default -q mailers -q ahoy
webpack: ./bin/webpack --watch --progress
ngrok: ngrok start jellyswitch