#! /bin/sh

dropdb jellyswitch_development
createdb jellyswitch_development
heroku local:run rake db:migrate
heroku local:run rake db:seed
