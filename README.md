# Bristlecone

Bristlecone is the project name for the backend and mobile-first web frontend for Jellyswitch.

## Development

- Rails 6.1.6.1
- Ruby 2.7
- Postgres 10.5

1. `bundle install`
2. Install [Heroku CLI](https://devcenter.heroku.com/articles/heroku-cli)
3. Install Redis:
  - `brew install redis`
  - `brew services start redis`
4. Install Elasticsearch:
  - `brew cask install homebrew/cask-versions/java8`
  - `brew install elasticsearch`
  - `brew services start elasticsearch`
5. Install [stripe-mock](https://github.com/stripe/stripe-mock) (to speed up testing)
  - `brew install stripe/stripe-mock/stripe-mock`
  - **NOTE** stripe-mock cannot be used to test for specific errors, so be sure to turn it off in development if testing for those.
  - `brew services start stripe-mock`
6. Ask dave for the `.env` file for environment variables
7. Run: `rails active_storage:install`
8. Postgres DB: `createdb bristlecone_development`
9. Run migrations: `heroku local:run rake db:migrate`
10. Run the server: `heroku local`

## Users, Admins, and Superadmins

All users have a record in the `users` table. Staff members of coworking spaces have the `admin` flag on their user set to `true`. Jellyswitch staff, developers, and so on, have both the `admin` and `superadmin` flag set to `true`. 

All users have associated stripe customers associated with them. So it's important to have the environment variables before taking this next step.

To get started, go ahead and hope the rails console (`heroku local:run rails c`) and create a new superadmin so you can log in:

```
$ u = User.create!(name: "Zero Cool", password: "password", email: "zerocool@hackers.com", admin: true, superadmin: true, approved: true)
$ result = CreateStripeCustomer.call(user: u)
```

## DNS & Operators

Bristlecone is a multi-tenant app, specifically on the `Operator` model. Every `operator` has a subdomain and all requests and database queries automatically select the correct operator as approprate (inferred from the subdomain).

As such, you need to have local DNS entries that point to your local development environment. Here's an example `/etc/hosts` file:

```
# Jellyswitch
127.0.0.1       www.jellyswitch.net
127.0.0.1       admin.jellyswitch.net
127.0.0.1       tml.jellyswitch.net
127.0.0.1       app.jellyswitch.net
127.0.0.1       beacon.jellyswitch.net
127.0.0.1       elevatebreck.jellyswitch.net
127.0.0.1       tahoemill.jellyswitch.net
127.0.0.1       skilockersteamboat.jellyswitch.net
127.0.0.1       innogrove.jellyswitch.net
127.0.0.1       capsity.jellyswitch.net
127.0.0.1       studio.jellyswitch.net
127.0.0.1       workshop.jellyswitch.net
127.0.0.1       incubateventures.jellyswitch.net

# Jellyswitch demo instances
127.0.0.1       demo0.jellyswitch.net
127.0.0.1       demo1.jellyswitch.net
127.0.0.1       demo2.jellyswitch.net
127.0.0.1       demo3.jellyswitch.net
127.0.0.1       demo4.jellyswitch.net
127.0.0.1       demo5.jellyswitch.net
127.0.0.1       demo6.jellyswitch.net
127.0.0.1       demo7.jellyswitch.net
127.0.0.1       demo8.jellyswitch.net
127.0.0.1       demo9.jellyswitch.net
127.0.0.1       demo10.jellyswitch.net
127.0.0.1       demo11.jellyswitch.net
127.0.0.1       demo12.jellyswitch.net
127.0.0.1       demo13.jellyswitch.net
127.0.0.1       demo14.jellyswitch.net
127.0.0.1       demo15.jellyswitch.net
127.0.0.1       demo16.jellyswitch.net
127.0.0.1       demo17.jellyswitch.net
127.0.0.1       demo18.jellyswitch.net
127.0.0.1       demo19.jellyswitch.net
127.0.0.1       demo20.jellyswitch.net
127.0.0.1       demo21.jellyswitch.net
127.0.0.1       demo22.jellyswitch.net
127.0.0.1       demo23.jellyswitch.net
127.0.0.1       demo24.jellyswitch.net
```

## Demo Instances

Open the rails console and create Subdomain records:

```
[1] pry(main)> 25.times { |n| Subdomain.create!(subdomain: "demo#{n}")
```

Go to `app.jellyswitch.net:3000` and click "New Operator". This will create take you to a form to create a new operator. Make sure to pick a subdomain that exists in the `/etc/hosts` file above.

Click the "Visit" button to see this instance.

## Local Elastic Search

`bin/rails searchkick:reindex:all` must be run initially.

If you encounter issues w/ elastic search, try running this command: 

`curl -u elastic:changeme -XPUT 'localhost:9200/_cluster/settings' -H 'Content-Type: application/json' -d '{"persistent":{"cluster.blocks.read_only":false}}'`

Can also try PUT to `/_all/_settings` this: `{
  "index.blocks.read_only_allow_delete": false
}`

(From [https://github.com/ankane/searchkick/issues/1040](https://github.com/ankane/searchkick/issues/1040)

## Problems

If you encounter ActiveStorge::FileNotFound, it is likely due to missing push notification certificate files. Run this:

```
Operator.all.map {|o| o.push_notification_certificate.purge }
```

in the rails console.