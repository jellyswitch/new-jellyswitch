
require 'pagy/extras/bootstrap'

Pagy::DEFAULT[:items] = 25
Pagy::DEFAULT[:breakpoints] = { 0 => [1, 0, 0, 1], 540 => [2, 3, 3, 2], 720 => [3, 4, 4, 3] }
Rails.application.config.assets.paths << Pagy.root.join('javascripts')
