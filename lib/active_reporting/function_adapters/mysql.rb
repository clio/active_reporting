# frozen_string_literal: true

module ActiveReporting
  module FunctionAdapters
    module Mysql
      # The list of available datetime values.
      #
      # @return [Array<Symbol>]
      #
      def self.datetime_precision_values
        %i[second minute hour day week month quarter year].freeze
      end

      # Whether the arg value is supported as a viable datetime
      # value for performing datetime functions.
      #
      def self.valid_datetime_precision_value?(value)
        datetime_precision_values.include?(value.to_sym)
      end

      # Generate a date truncation statement in MySQL
      # See https://www.postgresql.org/docs/10/static/functions-datetime.html#FUNCTIONS-DATETIME-TRUNC
      #
      # @param [String, Symbol] datetime_precision_value
      # @param [String] quoted_table_name
      # @param [String] column_name
      #
      def self.date_truncate(datetime_precision_value, quoted_table_name, column_name)
        # create_date_trunc_function unless date_trunc_function_exists?
        _active_reporting_date_trunc(datetime_precision_value, "#{quoted_table_name}.#{column_name}")
      end

      # NOTE:
      # (1) When truncated to "day" or any greater interval, removes
      #     the trailing "00:00:00" that is provided in Postgres
      # (2) Does not support decade, century, or millenium.
      #
      def self._active_reporting_date_trunc(datetime_precision_value, value)
        unless valid_datetime_precision_value?(datetime_precision_value)
          raise ArgumentError,
                "Interval value #{datetime_precision_value} is not valid for MySQL"
        end
        interval_precision = datetime_precision_value.upcase
        <<-SQL
          date_add(
            '0001-01-01',
            interval TIMESTAMPDIFF(#{interval_precision}, '0001-01-01', #{value}) #{interval_precision}
          )
        SQL
      end
    end
  end
end
