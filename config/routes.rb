Rails.application.routes.draw do
  namespace :api do
    resources :doors, only: [:index] do
      member do
        post :unlock
      end
    end
    resources :locations, only: [:index]

    namespace :v1 do
      post 'auth/login', to: 'auth#login'
      post 'auth/signup', to: 'auth#signup'
      post 'auth/forgot_password', to: 'auth#forgot_password'
      post 'auth/reset_password', to: 'auth#reset_password'
      post 'auth/refresh', to: 'auth#refresh'

      get 'me', to: 'users#me'
      patch 'me', to: 'users#update'
      post 'me/push_token', to: 'users#register_push_token'

      get 'dashboard', to: 'dashboard#show'
      get 'onboarding_status', to: 'dashboard#onboarding_status'

      resources :doors, only: [:index] do
        member do
          post :unlock
          get :punches
        end
      end

      resources :rooms, only: [:index] do
        member do
          get :availability
          get :time_slots
          get :pricing
        end
      end
      get 'reserve_now', to: 'rooms#reserve_now'

      resources :reservations, only: [:index, :create, :destroy]

      resources :events, only: [:index, :show] do
        member do
          post :rsvp
        end
      end

      # Memberships / Subscriptions
      get 'plans', to: 'subscriptions#plans'
      get 'my_subscription', to: 'subscriptions#my_subscription'
      resources :subscriptions, only: [:create, :destroy] do
        member do
          post :pause
          post :unpause
          patch :upgrade
          post :cancel_now
        end
      end

      # Day Passes
      get 'day_pass_types', to: 'day_passes#types'
      get 'my_day_passes', to: 'day_passes#index'
      resources :day_passes, only: [:create] do
        collection do
          post :redeem
        end
      end

      # Bulletin Board / Posts
      resources :posts, only: [:index, :show, :create] do
        resources :replies, only: [:create], controller: 'post_replies'
      end

      # Member Feedback / Messages
      resources :member_feedbacks, only: [:index, :show, :create] do
        member do
          post :reply
        end
      end

      # Invoices
      resources :invoices, only: [:index] do
        member do
          post :charge
        end
      end

      # Payment Method
      get 'payment_method', to: 'payment_methods#show'
      post 'payment_method', to: 'payment_methods#update'

      # Profile enhancements
      patch 'me/password', to: 'users#change_password'
      post 'me/profile_photo', to: 'users#upload_profile_photo'
      patch 'me/location', to: 'users#switch_location'
      post 'me/accept_terms', to: 'users#accept_terms'
      patch 'me/email_preferences', to: 'users#update_email_preferences'
      post 'me/purchase_credits', to: 'users#purchase_credits'
      get 'me/credit_info', to: 'users#credit_info'
      get 'me/usage', to: 'users#usage'
      delete 'me', to: 'users#destroy_account'

      # Announcements
      resources :announcements, only: [:index]

      # Check-in
      get 'checkins/current', to: 'checkins#current'
      resources :checkins, only: [:create, :destroy]

      # Stripe
      get 'stripe_config', to: 'stripe#show_config'
      post 'setup_intent', to: 'stripe#setup_intent'
      post 'validate_discount_code', to: 'stripe#validate_discount_code'

      # Organizations
      get 'my_organization', to: 'organizations#show'
      patch 'my_organization', to: 'organizations#update'
      post 'my_organization/add_member', to: 'organizations#add_member'
      post 'my_organization/remove_member', to: 'organizations#remove_member'
      get 'my_organization/invoices', to: 'organizations#invoices'
      get 'my_organization/payment_method', to: 'organizations#payment_method'

      # Admin namespace
      namespace :admin do
        # Feed
        get 'feed', to: 'feed#index'
        post 'feed', to: 'feed#create'
        post 'feed/:id/comments', to: 'feed#comment'
        delete 'feed/:id', to: 'feed#destroy'

        # Today's Activity
        get 'todays_activity', to: 'todays_activity#index'

        # Members
        get 'members', to: 'members#index'
        get 'members/unapproved', to: 'members#unapproved'
        get 'members/archived', to: 'members#archived'
        post 'members', to: 'members#create'
        get 'members/:id', to: 'members#show'
        patch 'members/:id', to: 'members#update'
        post 'members/:id/approve', to: 'members#approve'
        post 'members/:id/unapprove', to: 'members#unapprove'
        post 'members/:id/archive', to: 'members#archive'
        post 'members/:id/unarchive', to: 'members#unarchive'
        post 'members/:id/add_credits', to: 'members#add_credits'
        post 'members/:id/change_payment', to: 'members#change_payment'
        post 'members/:id/assign_subscription', to: 'members#assign_subscription'
        post 'members/:id/create_day_pass', to: 'members#create_day_pass'
        post 'members/:id/create_reservation', to: 'members#create_reservation'
        patch 'members/:id/edit_profile', to: 'members#edit_profile'
        post 'members/:id/create_invoice', to: 'members#create_invoice'
        post 'members/:id/cancel_subscription', to: 'members#cancel_subscription'
        post 'members/:id/cancel_subscription_now', to: 'members#cancel_subscription_now'
        post 'members/:id/reset_password', to: 'members#reset_password'

        # Reservations
        get 'reservations', to: 'reservations#index'
        get 'reservations/calendar', to: 'reservations#calendar'
        post 'reservations', to: 'reservations#create'
        patch 'reservations/:id/extend', to: 'reservations#extend'
        delete 'reservations/:id', to: 'reservations#destroy'

        # Rooms
        resources :rooms, only: [:index, :create, :update, :destroy]

        # Announcements
        get 'announcements', to: 'announcements#index'
        post 'announcements', to: 'announcements#create'
        patch 'announcements/:id', to: 'announcements#update'
        delete 'announcements/:id', to: 'announcements#destroy'

        # Events
        resources :events, only: [:index, :create, :update, :destroy]

        # Plans
        resources :plans, only: [:index, :create, :update] do
          member do
            post :toggle_visibility
            post :toggle_availability
          end
        end

        # Day Pass Types
        resources :day_pass_types, only: [:index, :create, :update]
        get 'day_passes', to: 'day_passes#index'

        # Invoices
        get 'invoices', to: 'invoices#index'
        post 'invoices', to: 'invoices#create'
        post 'invoices/:id/refund', to: 'invoices#refund'
        post 'invoices/:id/charge', to: 'invoices#charge'
        post 'invoices/:id/mark_paid', to: 'invoices#mark_paid'
        get 'accounting', to: 'invoices#accounting'

        # Offices & Leases
        resources :offices, only: [:index, :create, :update, :destroy]
        get 'office_leases', to: 'office_leases#index'
        get 'office_leases/renewals', to: 'office_leases#renewals'
        post 'office_leases', to: 'office_leases#create'

        # Organizations
        resources :organizations, only: [:index, :show, :create, :update]

        # Leads
        resources :leads, only: [:index, :show, :update] do
          resources :notes, only: [:create], controller: 'lead_notes'
        end

        # Doors
        get 'doors', to: 'doors#index'
        post 'doors/:id/open', to: 'doors#open'
        get 'doors/:id/punches', to: 'doors#punches'

        # Reports
        get 'reports', to: 'reports#index'
        get 'reports/revenue', to: 'reports#revenue'
        get 'reports/room_demand', to: 'reports#room_demand'
        get 'reports/members', to: 'reports#members'
        get 'reports/checkins', to: 'reports#checkins'
        get 'reports/ltv', to: 'reports#ltv'
        post 'reports/member_csv', to: 'reports#member_csv'

        # Feedback
        get 'feedbacks', to: 'feedbacks#index'
        get 'feedbacks/:id', to: 'feedbacks#show'
        post 'feedbacks/:id/reply', to: 'feedbacks#reply'
        post 'feedbacks/:id/dismiss', to: 'feedbacks#dismiss'

        # Email Templates
        resources :email_templates, only: [:index, :update] do
          member do
            post :toggle
            get :send_log
          end
        end

        # Campaigns
        resources :campaigns, only: [:index, :create, :update, :destroy] do
          member do
            post :send_campaign
            post :pause
            post :resume
            post :test_send
          end
        end

        # Discount Codes
        resources :discount_codes, only: [:index, :create, :update, :destroy]

        # Settings
        get 'settings', to: 'settings#show'
        patch 'settings', to: 'settings#update'
        get 'modules', to: 'settings#modules'
        patch 'modules', to: 'settings#update_modules'
        get 'notifications_config', to: 'settings#notifications'
        patch 'notifications_config', to: 'settings#update_notifications'

        # Posts (moderation)
        get 'posts', to: 'posts#index'
        delete 'posts/:id', to: 'posts#destroy'

        # Checkins
        get 'checkins', to: 'checkins#index'
        post 'checkins', to: 'checkins#create'

        # Recurring Reservations
        resources :recurring_reservations, only: [:index, :create, :destroy] do
          delete 'occurrences/:date', to: 'recurring_reservations#cancel_occurrence', on: :member
        end

        # Search
        get 'search', to: 'search#index'
      end
    end
  end

  namespace :mobile do
    get "/door_access", to: "door_access#index"
    get "/building_access_permissions", to: "door_access#building_access_permissions"
    get "/send_user_id_to_ios", to: "door_access#send_user_id_to_ios"
    get "/logout", to: "door_access#logout"
  end

  get "masquerade", to: "masquerade#new", as: :new_masquerade
  post "masquerade", to: "masquerade#update", as: :start_masquerading
  get "masquerade/current", to: "masquerade#show", as: :current_masquerading
  delete "masquerade", to: "masquerade#destroy", as: :end_masquerading

  ## Regular endpoints ##
  constraints subdomain: Rails.application.config.app_subdomain do
    require "sidekiq/web"
    mount Sidekiq::Web => "/sidekiq"
    # Root
    get "/", to: "landing#index"

    # Typeform
    get :welcome, to: "landing#welcome"

    # Authentication
    delete "/logout", to: "sessions#destroy", as: :logout
    post "/login", to: "sessions#create", as: :operator_login_create
    get "/login", to: "sessions#new", as: :operator_login
    get "/signup", to: "onboarding#new_user", as: :operator_signup
    get "/choose_operator", to: "sessions#choose_operator", as: :choose_operator
    get "/password_form", to: "sessions#password_form", as: :password_form
    post "/real_login", to: "sessions#real_create", as: :real_login

    get :stripe_connect_setup, to: "landing#stripe_connect_setup", as: :stripe_connect_setup

    resources :onboarding do
      collection do
        get :new_user
        post :create_user
        get :new_user_info
        post :create_user_and_locations
        get :choose_events
        get :add_event
        post :create_event
        get :daily_tasks
        post :create_daily_tasks
        get :favorite_parts
        post :create_favorite_parts
        get :finalize
      end
    end
    resources :operators
    resources :operator_surveys do
      collection do
        get :wait, to: "operator_surveys#wait"
      end
    end
    resources :webhooks do
      collection do
        post :stripe, to: "webhooks#stripe"
        post :sendgrid_events, to: "webhooks#sendgrid_events"
      end
    end
    resources :users
  end

  # Privacy Policy
  get "/privacy-policy", to: "operator/landing#privacy_policy"

  # Operator root
  root "operator/landing#index"

  # Operator Authentication
  delete "/logout", to: "operator/sessions#destroy", as: :operator_logout
  get "/logout", to: "sessions#destroy"
  post "/login", to: "operator/sessions#create"
  get "/login", to: "operator/sessions#new"
  get "/signup", to: "operator/users#new"

  # Landing
  get "landing/index", to: "operator/landing#index", as: :landing
  get "/home", to: "operator/landing#home"
  get "/wait", to: "operator/landing#wait"
  get "/approval_status", to: "operator/landing#approval_status"
  get "/choose", to: "operator/landing#choose"
  get "/activate", to: "operator/landing#activate"
  post "/activate_membership", to: "operator/landing#activate_membership"
  get "/upgrade", to: "operator/landing#upgrade"

  # Other
  get "/members_resources", to: "operator/landing#members_resources", as: :members_resources # TODO delete this
  get "/members_groups", to: "operator/landing#members_groups", as: :members_groups
  get "/offices_leases", to: "operator/landing#offices_leases", as: :offices_leases
  get "/plans_day_passes", to: "operator/landing#plans_day_passes", as: :plans_day_passes
  get "/customization", to: "operator/landing#customization", as: :customization
  get "/announcements_events", to: "operator/landing#announcements_events", as: :announcements_events
  post "/pause_membership/:id", to: "operator/pause_memberships#create", as: "pause_membership"
  delete "/pause_membership/:id", to: "operator/pause_memberships#destroy", as: "unpause_membership"

  # Admin namespace (for operator resources)
  namespace :operator do
    namespace :admin do
      resources :plan_categories do
        get :remove_plan
      end
      resources :subscriptions do
        collection do
          post :confirm
          get :choose_start_date
        end
      end
      resources :day_passes
    end
  end

  # Product Email Templates
  resources :product_email_templates, controller: "operator/product_email_templates", only: [:index, :edit, :update] do
    member do
      get :toggle_enabled
    end
    collection do
      get :send_log
    end
  end

  # Alphabetized Member Resources
  resources :accounting, controller: "operator/accounting" do
    collection do
      get "expenses", to: "operator/accounting#expenses", as: :expenses
      get "update_expenses", to: "operator/accounting#update_expenses"
    end
  end
  resources :announcements, controller: "operator/announcements"
  resources :app_configs, controller: "operator/app_configs"
  resources :checkins, controller: "operator/checkins" do
    collection do
      get :required, to: "operator/checkins#required"
    end
  end
  resources :childcare, controller: "operator/childcare"
  resources :child_profiles, controller: "operator/child_profiles"
  resources :childcare_reservations, controller: "operator/childcare_reservations" do
    collection do
      get :select_slot, to: "operator/childcare_reservations#select_slot"
    end
  end
  resources :childcare_slots, controller: "operator/childcare_slots"
  resources :childcare_reservation_purchases, controller: "operator/childcare_reservation_purchases" do
    collection do
      post :confirm, to: "operator/childcare_reservation_purchases#confirm"
    end
  end
  resources :credit_purchases, controller: "operator/credit_purchases" do
    collection do
      get :confirm, to: "operator/credit_purchases#confirm"
    end
  end
  resources :day_passes, controller: "operator/day_passes" do
    collection do
      get :code, to: "operator/day_passes#code"
      post :code, to: "operator/day_passes#redeem_code"
      get :redeem_paid, to: "operator/day_passes#redeem_paid"
    end
  end
  resources :day_pass_types, controller: "operator/day_pass_types" do
    get :available, to: "operator/day_pass_types#available"
    get :visible, to: "operator/day_pass_types#visible"
    get :always_allow_building_access, to: "operator/day_pass_types#always_allow_building_access"
    post :unarchive, to: "operator/day_pass_types#unarchive"
    collection do
      get :archived, to: "operator/day_pass_types#archived"
    end
  end
  resources :discount_codes, controller: "operator/discount_codes"
  resources :doors, controller: "operator/doors" do
    get "open", to: "operator/doors#open"
    post :unarchive, to: "operator/doors#unarchive"
    collection do
      get "keys", to: "operator/doors#keys"
      get :archived, to: "operator/doors#archived"
    end
  end
  resources :door_punches, controller: "operator/door_punches"
  resources :events, controller: "operator/events" do
    collection do
      get :past, to: "operator/events#past"
    end
    resources :analytics, controller: "operator/events/analytics"
    resources :rsvps, controller: "operator/rsvps" do
      collection do
        get :going, to: "operator/rsvps#going"
        get :not_going, to: "operator/rsvps#not_going"
        get :register, to: "operator/rsvps#register"
        get :login, to: "operator/rsvps#login"
      end
    end
  end
  resources :feed_items, controller: "operator/feed_items" do
    collection do
      get :questions
      get :activity
      get :notes
      get :financial
    end
    member do
      post "set_expense_status"
      post "unset_expense_status"
    end
    resources :comments, controller: "operator/feed_item_comments", only: [:create]
  end
  resources :invoices, only: [:index, :new, :create], controller: "operator/invoices" do
    resources :refunds, only: [:create], controller: "operator/refunds"
    get :mark_paid, to: "operator/mark_invoices_paid#update"
    collection do
      get :groups, to: "operator/invoices#groups"
      get :open, to: "operator/invoices#open"
      get :recent, to: "operator/invoices#recent"
      get :delinquent, to: "operator/invoices#delinquent"
    end
    get :charge
  end
  resources :leads, controller: "operator/leads"
  resources :lead_notes, controller: "operator/lead_notes"
  resources :locations, controller: "operator/locations" do
    get :allow_hourly, to: "operator/locations#allow_hourly"
    get :new_users_get_free_day_pass, to: "operator/locations#new_users_get_free_day_pass"
    get :visible, to: "operator/locations#visible"
  end
  resources :member_feedbacks, controller: "operator/member_feedbacks" do
    member do
      post :reply
      post :dismiss
    end
    collection do
      get :my_feedback
    end
  end
  resources :modules, controller: "operator/modules" do
    collection do
      get :announcements
      get :bulletin_board
      get :childcare
      get :credits
      get :crm
      get :door_integration
      get :events
      get :offices
      get :rooms
      get :reservation_credits_settings
      get :childcare_reservations_settings
    end
  end
  resources :notifications, controller: "operator/notifications" do
    collection do
      get :checkins
      get :day_passes
      get :feedback
      get :memberships
      get :posts
      get :reservations
      get :paid_room_reservations
      get :refunds
      get :signups
    end
    member do
      get :toggle_workflow
    end
  end
  resources :unsubscribes, controller: "operator/unsubscribes", only: [:show]
  post "email_preferences", to: "operator/users#toggle_email_preferences", as: :member_toggle_email
  resources :campaigns, controller: "operator/admin/campaigns" do
    member do
      post :send_campaign
      post :pause
      post :resume
      post :clone
      get :preview
      post :test_send
      post :exclude_recipient
    end
  end
  resources :onboarding, controller: "operator/onboarding", as: :operator_onboarding do
    collection do
      get :new_membership_plan
      post :create_membership_plan
      get :new_day_pass_type
      post :create_day_pass_type
      get :new_room
      post :create_room
      get :add_members
      get :new_member
      post :create_member
      get :new_stripe_members
      post :create_stripe_members
      get :new_kisi
      post :create_kisi
      get :new_door
      post :create_door
      post :destroy_door
      get :skip
    end
  end
  resources :offices, controller: "operator/offices" do
    collection do
      get :available, to: "operator/offices#available"
      get :upcoming_renewals, to: "operator/offices#upcoming_renewals"
      get :archived, to: "operator/offices#archived"
    end
  end
  resources :lease_renewal_requests, controller: "operator/lease_renewal_requests", only: [:index, :show] do
    member do
      post :accept
      post :request_modification
      get :admin_review
      post :admin_approve
      post :admin_decline
      post :admin_force_approve
    end
  end

  resources :office_leases, controller: "operator/office_leases" do
    get :renewal, to: "operator/office_leases#renewal"
    get :edit_price, to: "operator/office_leases#edit_price"
    patch :update_price, to: "operator/office_leases#update_price"
    post :convert_to_organization, to: "operator/office_leases#convert_to_organization"
  end
  delete "destroy_office_lease_now/:id", to: "operator/office_leases#destroy_office_lease_now", as: "destroy_office_lease_now"
  resources :organizations, controller: "operator/organizations" do
    post :add_member, to: "operator/organization_members#create"
    get :billing, to: "operator/organizations#billing"
    post :billing, to: "operator/organization_billing#create"
    get :credit_card, to: "operator/organizations#credit_card"
    get :invoices, to: "operator/organizations#invoices"
    get :leases, to: "operator/organizations#leases"
    get :ltv, to: "operator/organizations#ltv"
    get :members, to: "operator/organizations#members"
    get :out_of_band, to: "operator/organizations#out_of_band"
    get :payment_method, to: "operator/organizations#payment_method"
  end
  resources :operators, as: :operator_operators, controller: "operator/operators" do
    get :approval_required, to: "operator/operators#approval_required"
    get :checkin_required, to: "operator/operators#checkin_required"
    get :stripe_connect_setup, to: "operator/operators/stripe_connect_setup"
  end
  resources :password_resets, only: [:new, :create, :edit, :update], controller: "operator/password_resets"
  resources :email_confirmations, only: [:show], controller: "operator/email_confirmations"
  post :resend_confirmation, to: "operator/email_confirmations#resend"
  resources :plan_categories, controller: "operator/plan_categories"
  resources :plans, controller: "operator/plans" do
    get :toggle_visibility, to: "operator/plans#toggle_visibility"
    get :toggle_availability, to: "operator/plans#toggle_availability"
    get :toggle_building_access, to: "operator/plans#toggle_building_access"
    post :unarchive, to: "operator/plans#unarchive"
    collection do
      get :archived, to: "operator/plans#archived"
    end
  end
  resources :posts, controller: "operator/posts"
  resources :post_replies, controller: "operator/post_replies", only: [:create]
  resources :reports, controller: "operator/reports" do
    collection do
      get :member_csv
      get :active_members
      get :active_lease_members
      get :active_leases
      get :last_30_day_passes
      get :total_members
      get :membership_breakdown
      get :revenue
      get :monetization
      get :checkins
      get :ltv
      get :room_demand
      get :inactive_members
      get :suppressed_members
      post :suppress_marketing
      post :unsuppress_marketing
      post :toggle_email_opt_out
      post :dismiss_inactive
      post :create_location_event
      delete :delete_location_event
    end
  end
  resources :todays_activity, controller: "operator/todays_activity", only: [:index]

  resources :recurring_reservations, controller: "operator/recurring_reservations", only: [:new, :create, :show, :index] do
    collection do
      post :check_conflicts
    end
    member do
      put :cancel_series
      put :cancel_occurrence
    end
  end
  resources :reservations, controller: "operator/reservations", except: [:index, :new] do
    collection do
      get :choose_day, to: "operator/reservations#choose_day"
      get :choose_time, to: "operator/reservations#choose_time"
      post :choose_time_post, to: "operator/reservations#choose_time_post"
      get :choose_duration, to: "operator/reservations#choose_duration"
      get :choose_member, to: "operator/reservations#choose_member"
      get :confirm, to: "operator/reservations#confirm"
      get :create_reservation, to: "operator/reservations#create_reservation"
      post :update_billing_and_create_reservation, to: "operator/reservations#update_billing_and_create_reservation"
      get :today, to: "operator/reservations#today"

      get :calendar, to: "operator/reservations#calendar"
      get :available_time_slots, to: "operator/reservations#available_time_slots"
      get :available_rooms, to: "operator/reservations#available_rooms"
      get :max_available_duration, to: "operator/reservations#max_available_duration"
      get :room_price_and_details, to: "operator/reservations#room_price_and_details"
      get :needs_billing, to: "operator/reservations#needs_billing"

      get :daily_counts, to: "operator/reservations#daily_counts"
      get :daily_details, to: "operator/reservations#daily_details"

      get :reserve_now, to: "operator/instant_book#index"
      get :instant_book, to: "operator/instant_book#index"
      get :instant_book_price, to: "operator/instant_book#price"
    end

    member do
      get :available_extension_durations, to: "operator/reservations#available_extension_durations"
      get :calculate_additional_hour_price, to: "operator/reservations#calculate_additional_hour_price"
      put :extend_reservation, to: "operator/reservations#extend_reservation"
      put :end_now, to: "operator/reservations#end_now"
      put :update_note, to: "operator/reservations#update_note"
    end
  end
  resources :rooms, controller: "operator/rooms" do
    get "day/:day/:month/:year", to: "operator/rooms#day", as: :day_availability
  end
  resources :search_results, only: [:new, :create], controller: "operator/search_results" do
    collection do
      get :query, to: "operator/search_results#query"
    end
  end
  resource :set_location, only: [:edit, :update], controller: "operator/set_location"
  resources :subscriptions, controller: "operator/subscriptions"
  delete "destroy_subscription_now/:id", to: "operator/subscriptions#destroy_subscription_now", as: "destroy_subscription_now"
  resources :users, controller: "operator/users" do
    collection do
      get "add_member", to: "operator/users#add_member"
      get :archived, to: "operator/users#archived"
      get :search_archived, to: "operator/users#search_archived"
      get :unapproved, to: "operator/users#unapproved"
      get :search, to: "operator/users#search"
      get :confirmation_pending, to: "operator/users#confirmation_pending"
    end
    get :about, to: "operator/users#about"
    post :add_childcare_reservations, to: "operator/users#add_childcare_reservations"
    post :add_credits, to: "operator/users#add_credits"
    get :admin_day_passes, to: "operator/users#admin_day_passes"
    get :admin_invoices, to: "operator/users#admin_invoices"
    get :approve, to: "operator/users#approve"
    get :archive, to: "operator/users#archive"
    get :billing, to: "operator/users#edit_billing"
    post :billing, to: "operator/users#update_billing"
    get :bill_to_organization, to: "operator/users#bill_to_organization"
    get :checkins, to: "operator/users#checkins"
    get :childcare, to: "operator/users#childcare"
    get :credit_card, to: "operator/users#credit_card"
    get :credits, to: "operator/users#credits"
    get "change_password", to: "operator/users#change_password"
    get :day_passes, to: "operator/users#day_passes"
    get :invoices, to: "operator/users#invoices"
    get :ltv, to: "operator/users#ltv"
    get :membership, to: "operator/users#membership"
    get :memberships, to: "operator/users#memberships"
    get :out_of_band, to: "operator/users#out_of_band"
    get :organization, to: "operator/users#organization"
    get :past_reservations, to: "operator/users#past_reservations"
    get :payment_method, to: "operator/users#payment_method"
    get :remove_from_organization, to: "operator/users#remove_from_organization"
    get :reservations, to: "operator/users#reservations"
    get :unapprove, to: "operator/users#unapprove"
    get :unarchive, to: "operator/users#unarchive"
    get :usage, to: "operator/users#usage"
    get :change_account, to: "operator/users#change_account"
    patch "update_password", to: "operator/users#update_password"
    patch "update_organization", to: "operator/users#update_organization"
    patch "update_payment_method", to: "operator/users#update_payment_method"
  end
  resources :weekly_updates, controller: "operator/weekly_updates"

  resources :mentions, controller: "operator/mentions", only: [:index]

  # Return proper empty responses for common bot/crawler requests
  match '/.well-known/assetlinks.json', to: proc { [200, { 'Content-Type' => 'application/json' }, ['[]']] }, via: :get
  match '/sitemap.xml', to: proc { [404, { 'Content-Type' => 'application/xml' }, ['']] }, via: :get
  match '/sitemap_index.xml', to: proc { [404, { 'Content-Type' => 'application/xml' }, ['']] }, via: :get
  match '/robots.txt', to: proc { [200, { 'Content-Type' => 'text/plain' }, ["User-agent: *\nAllow: /\n"]] }, via: :get

  # Block common bot/scanner probe paths (WordPress, PHP, etc.)
  match '/wp-json(/*path)', to: proc { [404, {}, ['']] }, via: :all
  match '/wp-admin(/*path)', to: proc { [404, {}, ['']] }, via: :all
  match '/wp-login.php', to: proc { [404, {}, ['']] }, via: :all
  match '/wp-content(/*path)', to: proc { [404, {}, ['']] }, via: :all
  match '/wp-includes(/*path)', to: proc { [404, {}, ['']] }, via: :all
  match '/xmlrpc.php', to: proc { [404, {}, ['']] }, via: :all
  match '/.env', to: proc { [404, {}, ['']] }, via: :all
  match '/vendor(/*path)', to: proc { [404, {}, ['']] }, via: :all

  # Catch bot scanners using prefixed WordPress paths (e.g. /cms/wp-includes/, /wp2/wp-admin/)
  match '/*path', to: proc { [404, {}, ['']] }, via: :all,
    constraints: ->(req) { req.path.match?(%r{/wp-(?:includes|content|admin|json|login)|/xmlrpc\.php|/wlwmanifest\.xml|\.php$}) }
end
