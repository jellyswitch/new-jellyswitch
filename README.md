# Bristlecone

Bristlecone is the project name for the backend and mobile-first web frontend for Jellyswitch.

## Development

- Rails 5.2.2
- Ruby 2.4.4
- Postgres 10.5

1. `bundle install`
2. `gem install heroku`
3. Ask dave for the `.env` file for environment variables
4. Postgres DB: `createdb bristlecone_development`
5. Run migrations: `heroku local:run rake db:migrate`
6. Seed data: `heroku local:run rake db:seed`
7. Run the server: `heroku local`