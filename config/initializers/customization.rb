Rails.application.config.x.customization.name = ENV['INSTANCE_NAME'] || "Bristlecone"
Rails.application.config.x.customization.slug = Rails.application.config.x.customization.name.parameterize
Rails.application.config.x.customization.snippet = ENV['INSTANCE_SNIPPET'] || "Generic snippet here"
Rails.application.config.x.customization.background = ENV['INSTANCE_BACKGROUND'] || "defaultbackground.png"
Rails.application.config.x.customization.wifi_name = ENV['WIFI_NAME'] || "not set"
Rails.application.config.x.customization.wifi_password = ENV['WIFI_PASSWORD'] || "not set"
Rails.application.config.x.customization.building_address = ENV['BUILDING_ADDRESS'] || "not set"
Rails.application.config.x.customization.logo = ENV['INSTANCE_LOGO']

# Theming
Rails.application.config.x.customization.primary = ENV['THEME_PRIMARY']
Rails.application.config.x.customization.secondary = ENV['THEME_SECONDARY']
Rails.application.config.x.customization.success = ENV['THEME_SUCCESS']
Rails.application.config.x.customization.danger = ENV['THEME_DANGER']
Rails.application.config.x.customization.info = ENV['THEME_INFO']
Rails.application.config.x.customization.warning = ENV['THEME_WARNING']
Rails.application.config.x.customization.light = ENV['THEME_LIGHT']
Rails.application.config.x.customization.dark = ENV['THEME_DARK']

# Stripe
Rails.application.config.x.customization.day_pass_cents = ENV['DAY_PASS_COST_CENTS'].to_i
