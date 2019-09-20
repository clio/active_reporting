source 'https://rubygems.org'
# Specify your gem's dependencies in active_reporting.gemspec
gemspec

gem 'simplecov', require: false

rails = ENV['RAILS'] || '5-2'
db = ENV['DB'] || 'sqlite'

case rails
when '4-2'
  gem 'activerecord', '~> 4.2.0'
when '5-1'
  gem 'activerecord', '~> 5.1.0'
when '5-2'
  gem 'activerecord', '~> 5.2.0'
when '6-0'
  gem 'activerecord', '6.0.0'
end

case rails
when '4-2'
  case ENV['DB']
  when 'pg'
    gem 'pg', '~> 0.18'
  when 'mysql'
    gem 'mysql2', '~> 0.3.18'
  when 'sqlite'
    gem 'sqlite3', '~> 1.3.0'
  end
end
