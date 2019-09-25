# frozen_string_literal: true

require 'forwardable'
module ActiveReporting
  class Report
    AGGREGATE_FUNCTION_OPERATORS = {
      eq:   '=',
      gt:   '>',
      gte:  '>=',
      lt:   '<',
      lte:  '<='
    }.freeze

    extend Forwardable
    def_delegators :@metric, :fact_model, :model

    def initialize(metric, dimension_identifiers: true, dimension_filter: {}, dimensions: [], metric_filter: {})
      @metric = metric.is_a?(Metric) ? metric : ActiveReporting.fetch_metric(metric)
      raise UnknownMetric, "Unknown metric #{metric}" if @metric.nil?

      @dimension_identifiers  = dimension_identifiers
      local_dimensions        = ReportingDimension.build_from_dimensions(fact_model, Array(dimensions))
      @dimensions             = (@metric.dimensions + local_dimensions).uniq
      @metric_filter          = @metric.metric_filter.merge(metric_filter)
      @ordering               = @metric.order_by_dimension
      partition_dimension_filters dimension_filter
    end

    # Builds and executes a query, returning the raw result
    #
    # @return [Array]
    def run
      @run ||= build_data
    end

    private ######################################################################

    def build_data
      @data = model.connection.exec_query(statement).to_hash
      apply_dimension_callbacks
      @data
    end

    def partition_dimension_filters(user_dimension_filter)
      @dimension_filters = { ransack: {}, scope: {}, lambda: {} }
      user_dimension_filter.merge(@metric.dimension_filter).each do |key, value|
        dm = fact_model.find_dimension_filter(key.to_sym)
        @dimension_filters[dm.type][dm] = value
      end
    end

    # Builds the sql statement to execute
    #
    # @return [String]
    def statement
      case @metric.aggregate
      when :sum
        parts = {
          select: select_statement,
          joins: dimension_joins,
          having: having_statement,
          order: order_by_statement
        }

        statement = ([model] + parts.keys).inject do |chain, method|
          chain.public_send(method, parts[method])
        end

        statement = process_scope_dimension_filter(statement)
        statement = process_lambda_dimension_filter(statement)
        statement = process_ransack_dimension_filter(statement)

        # The original gem did not handle has_many relationships. In order to support
        # has_many, we need to first do an inner query to select out distinct rows _before_
        # attempting the sum. Therefore we build up the query piece
        # by piece rather than using the basic statement.

        # This is out of hand, take a step back and try again
# ***************************
        # TODO: CLEAN UP THESE COMMENTS

        # We need to ensure that we include all columns from the original SELECT query in the
        # inner select, so grab these first. Also save each renamed column names (aka "AS name")
        # into a separate array to be included in the outer query

        # Drop the first element here because it's the SUM and we'll add that later
        orig_select = parts[:select].drop(1)#.join(', ').remove("\n").squeeze(' ') PUT THIS BACK TO CLEAN IT UP
        orig_renames = []
        orig_select.each do |sel|
          orig_renames << sel.split(' AS ').last#.remove("\n").squeeze(' ') YOU DONT NEED THIS HERE PROBABLY
        end

        # In some situations the column we're summing over is not included as a part of the aggregation
        # in the inner query. In such cases we must explicitly select the desired column in the inner
        # query, so that we can sum over it in the outer query.
        if select_aggregate.include?("CASE")
          selection_metric = select_aggregate.split('CASE WHEN ').last.split(' ').first
        else
          selection_metric = ''
        end

        # ORIG
        #inner_columns = ",#{inner_select_statement.join(', ')}"
        #if selection_metric && !inner_columns.include?(selection_metric)
        #  inner_columns = "#{selection_metric}#{inner_columns}"
        #end

        # UPDATED
        inner_columns = inner_select_statement #<----inner_select_statement is where custom_created_at is coming from fwiw
        inner_columns << selection_metric if selection_metric

        #inner_columns = merge_column_lists(orig_select, inner_columns) # STILL SOMETHING WRONG HERE YOU NEED TO SEE
        inner_columns << orig_select
        inner_columns << fact_model.measure.to_s
        inner_columns = inner_columns.flatten.uniq.join(', ').remove("\n").squeeze(' ') # remove and squeeze just to make it prettier

        #ORIG
        #inner_select = "SELECT #{distinct}, #{orig_select.join(', ')}, #{fact_model.measure.to_s} #{inner_columns}"
        inner_select = "SELECT #{distinct}, #{inner_columns}"
        inner_from = statement.to_sql.split('FROM').last
        group_by = outer_group_by_statement.join(', ')

        outer_columns = merge_column_lists(outer_select_statement, orig_renames) # YOU CAN PROBABLY JUST USE UNIQUE HERE
        #outer_select = "#{outer_select_statement.join(', ')}, #{orig_renames.join(', ')}" # TODO: ENSURE NO DUPLICATES in what you select
        outer_select = "#{outer_columns.join(', ')}"
#*************************************

        # Second attempt - anything extra that's not used in the block below can be deleted
        outer_columns = ([select_statement.first] << orig_renames).flatten.uniq.join(', ')
        inner_columns = (select_statement.drop(1) << [selection_metric, fact_model.measure.to_s]).flatten.uniq.reject(&:blank?).join(', ').remove("\n").squeeze(' ')
        inner_from = statement.to_sql.split('FROM').last
        group_by = outer_group_by_statement.join(', ')
        "SELECT #{outer_columns} FROM(SELECT #{distinct}, #{inner_columns} FROM #{inner_from}) AS T GROUP BY #{group_by}"

        # Finally, construct the query we want and return it as a string
        #"SELECT #{outer_select} FROM(#{inner_select} FROM #{inner_from}) AS T GROUP BY #{group_by}"

      else
        parts = {
          select: select_statement,
          joins: dimension_joins,
          group: group_by_statement,
          having: having_statement,
          order: order_by_statement
        }

        statement = ([model] + parts.keys).inject do |chain, method|
          chain.public_send(method, parts[method])
        end

        statement = process_scope_dimension_filter(statement)
        statement = process_lambda_dimension_filter(statement)
        statement = process_ransack_dimension_filter(statement)

        statement.to_sql
      end
    end

    # Helper to merge two lists of columns into a single SELECT statement
    # SQL does not permit duplicate column names within a select
    #
    def merge_column_lists(list1, list2)
      (list1 + list2).uniq
    end

    def select_statement
      ss = ["#{select_aggregate} AS #{@metric.name}"]
      ss += @dimensions.map { |d| d.select_statement(with_identifier: @dimension_identifiers) }
      ss.flatten
    end

    def outer_select_statement
      ss = ["#{select_aggregate} AS #{@metric.name}"]
      ss += @dimensions.map { |d| d.select_statement_no_rename(with_identifier: @dimension_identifiers) }
      ss.flatten
    end

    def inner_select_statement
      ss = @dimensions.map { |d| d.select_statement_always_rename(with_identifier: @dimension_identifiers) }
      ss.flatten
    end

    def distinct
      "DISTINCT `#{@metric.model.name_without_component.downcase.pluralize}`.`id`"
    end

    def select_aggregate
      case @metric.aggregate
      when :count
        count_params = if @metric.aggregate_expression
                         "#{distinct}, #{@metric.aggregate_expression}"
                       else
                         distinct
                       end

        "COUNT(#{count_params})"
      else
        "#{@metric.aggregate.to_s.upcase}(#{@metric.aggregate_expression || fact_model.measure})"
      end
    end

    def dimension_joins
      @dimensions.select { |d| d.type == :standard }.map { |d| d.name.to_sym }
    end

    def group_by_statement
      @dimensions.map { |d| d.group_by_statement(with_identifier: @dimension_identifiers) }
    end

    def outer_group_by_statement
      @dimensions.map { |d| d.group_by_statement_with_rename(with_identifier: @dimension_identifiers) }
    end

    def process_scope_dimension_filter(chain)
      @dimension_filters[:scope].each do |dm, args|
        chain = if [true, 'true'].include?(args)
                  chain.public_send(dm.name)
                else
                  chain.public_send(dm.name, args)
                end
      end
      chain
    end

    def process_lambda_dimension_filter(chain)
      @dimension_filters[:lambda].each do |df, args|
        chain = if [true, 'true'].include?(args)
                  chain.scoping { model.instance_exec(&df.body) }
                else
                  chain.scoping { model.instance_exec(args, &df.body) }
                end
      end
      chain
    end

    def process_ransack_dimension_filter(chain)
      ransack_hash = {}
      @dimension_filters[:ransack].each do |dm, value|
        ransack_hash[dm.name] = value
      end
      chain = chain.ransack(ransack_hash).result if ransack_hash.present?
      chain
    end

    def having_statement
      @metric_filter.map do |operator, value|
        "#{select_aggregate} #{AGGREGATE_FUNCTION_OPERATORS[operator]} #{value.to_f}"
      end.join(' AND ')
    end

    def order_by_statement
      [].tap do |o|
        @ordering.each do |dimension_key, direction|
          dim = @dimensions.detect { |d| d.name.to_sym == dimension_key.to_sym }
          o << dim.order_by_statement(direction: direction) if dim
        end
      end
    end

    def apply_dimension_callbacks
      @dimensions.each do |dimension|
        callback = dimension.label_callback
        next unless callback
        @data.each do |hash|
          hash[dimension.name.to_s] = callback.call(hash[dimension.name.to_s])
        end
      end
    end
  end
end
