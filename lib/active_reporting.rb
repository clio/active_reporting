require 'active_record'
require 'active_reporting/active_record_adaptor'
require 'active_reporting/configuration'
require 'active_reporting/dimension'
require 'active_reporting/dimension_filter'
require 'active_reporting/metric'
require 'active_reporting/fact_model'
require 'active_reporting/report'
require 'active_reporting/reporting_dimension'
require 'active_reporting/version'

begin
  require 'ransack'
  ActiveReporting::Configuration.ransack_available = true
rescue
  ActiveReporting::Configuration.ransack_available = false
end

ActiveRecord::Base.extend(ActiveReporting::ActiveRecordAdaptor)

module ActiveReporting
  InvalidDimensionLabel = Class.new(StandardError)
  RansackNotAvailable = Class.new(StandardError)
  UnknownAggregate = Class.new(StandardError)
  UnknownDimension = Class.new(StandardError)
  UnknownDimensionFilter = Class.new(StandardError)
end
