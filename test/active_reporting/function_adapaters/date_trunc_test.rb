require 'test_helper'

class ActiveReporting::FunctionAdapters::DateTruncTest < Minitest::Test
  def adapter
    db_name = ActiveRecord::Base.connection.adapter_name
    ActiveReporting::FunctionAdapters::MAPPINGS[db_name]
  end

  def assert_time_effectively_equal(value1, value2)
    assert Time.parse(value1.chomp('UTC')) == Time.parse(value2.chomp('UTC'))
  end

  def pg?
    ENV['DB'] == 'pg'
  end

  def mysql?
    ENV['DB'] == 'mysql'
  end

  def perform_query(interval, time)
    stmt = adapter._active_reporting_date_trunc(
      interval, "TIMESTAMP '#{time.strftime('%F %T')}'"
    )
    ActiveRecord::Base.connection.exec_query("SELECT #{stmt} AS foo")
  end

  def test_date_trunc_returns_minute_data
    return unless adapter.present?
    time = Time.parse('2018-09-29 12:15:45')

    result = perform_query('minute', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-09-29 12:15:00')
  end

  def test_date_trunc_returns_hourly_data
    return unless adapter.present?
    time = Time.parse('2018-09-29 12:15:45')

    result = perform_query('hour', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-09-29 12:00:00')
  end

  def test_date_trunc_returns_day_data
    return unless adapter.present?
    time = Time.parse('2018-09-29 12:15:45')

    result = perform_query('day', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-09-29 00:00:00')
  end

  # Postgres and Ruby follow ISO standards for Monday being the start of
  # the week -- Postgres' `date_trunc` function follows that convention.
  # Here we test that our MySQL port does the same.
  #
  def test_date_trunc_returns_monday_for_week_start
    return unless adapter.present?
    time = Date.parse('2018-09-29').beginning_of_day

    result = perform_query('week', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-09-24 00:00:00')
  end

  def test_week_truncation_when_date_is_a_sunday
    return unless adapter.present?
    time = Date.parse('2018-06-03').beginning_of_day

    result = perform_query('week', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-05-28 00:00:00')
  end

  def test_date_trunc_returns_month_data
    return unless adapter.present?
    time = Date.parse('2018-09-29').beginning_of_day

    result = perform_query('month', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-09-01 00:00:00')
  end

  def test_date_trunc_quarter_data_in_first_month_of_quarter
    return unless adapter.present?
    time = Date.parse('2018-07-29').beginning_of_day

    result = perform_query('quarter', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-07-01 00:00:00')
  end

  def test_date_trunc_quarter_data_in_second_month_of_quarter
    return unless adapter.present?
    time = Date.parse('2018-08-29').beginning_of_day

    result = perform_query('quarter', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-07-01 00:00:00')
  end

  def test_date_trunc_quarter_data_in_third_month_of_quarter
    return unless adapter.present?
    time = Date.parse('2018-09-29').beginning_of_day

    result = perform_query('quarter', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-07-01 00:00:00')
  end

  def test_date_trunc_returns_year_data
    return unless adapter.present?
    time = Date.parse('2018-09-29').beginning_of_day

    result = perform_query('year', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2018-01-01 00:00:00')
  end

  def test_date_trunc_returns_pre_1900_year_data
    return unless adapter.present?
    time = Date.parse('1718-09-29').beginning_of_day

    result = perform_query('year', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '1718-01-01 00:00:00')
  end

  def test_date_trunc_returns_decade_data
    return unless adapter.present?
    time = Date.parse('2018-09-29').beginning_of_day

    result = perform_query('decade', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '2010-01-01 00:00:00')
  end

  def test_date_trunc_returns_century_data
    return unless adapter.present?
    time = Date.parse('1718-09-29').beginning_of_day

    result = perform_query('century', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '1701-01-01 00:00:00')
  end

  def test_date_trunc_returns_millennium_data
    return unless adapter.present?
    time = Date.parse('1718-09-29').beginning_of_day

    result = perform_query('millennium', time)
    assert_time_effectively_equal(result.first['foo'].to_s, '1001-01-01 00:00:00')
  end
end
