# tempoarily disable logging of ruby 2.7 deprecation warnings
# to keep logs clean
Warning[:deprecated] = true unless Rails.env == "development"
