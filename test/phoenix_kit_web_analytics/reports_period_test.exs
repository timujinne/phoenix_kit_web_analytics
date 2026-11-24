defmodule PhoenixKitWebAnalytics.ReportsPeriodTest do
  @moduledoc """
  The parts of `PhoenixKitWebAnalytics.Reports` that are pure date maths — no
  database needed, so these run everywhere.
  """

  use ExUnit.Case, async: true

  doctest PhoenixKitWebAnalytics.Reports

  alias PhoenixKitWebAnalytics.Reports

  describe "period_range/2" do
    test "today covers exactly one day, ending at tomorrow's start" do
      {from, to} = Reports.period_range("today", ~U[2026-03-04 15:30:00Z])

      assert DateTime.to_date(from) == ~D[2026-03-04]
      assert from.hour == 0
      assert DateTime.to_date(to) == ~D[2026-03-05]
    end

    test "yesterday ends where today begins" do
      {from, to} = Reports.period_range("yesterday", ~U[2026-03-04 15:30:00Z])

      assert DateTime.to_date(from) == ~D[2026-03-03]
      assert DateTime.to_date(to) == ~D[2026-03-04]
    end

    test "7d includes today, so it spans seven days" do
      {from, to} = Reports.period_range("7d", ~U[2026-03-10 09:00:00Z])

      assert DateTime.to_date(from) == ~D[2026-03-04]
      assert DateTime.to_date(to) == ~D[2026-03-11]
      assert DateTime.diff(to, from, :day) == 7
    end

    test "14d includes today, so it spans fourteen days" do
      {from, to} = Reports.period_range("14d", ~U[2026-03-14 09:00:00Z])

      assert DateTime.to_date(from) == ~D[2026-03-01]
      assert DateTime.to_date(to) == ~D[2026-03-15]
    end

    test "30d and 90d span their nominal number of days" do
      now = ~U[2026-03-10 09:00:00Z]

      {from_30, to_30} = Reports.period_range("30d", now)
      {from_90, to_90} = Reports.period_range("90d", now)

      assert DateTime.diff(to_30, from_30, :day) == 30
      assert DateTime.diff(to_90, from_90, :day) == 90
    end

    test "every window ends in the future, so today's hits are included" do
      now = DateTime.utc_now()

      for {period, _label} <- Reports.periods() do
        {_from, to} = Reports.period_range(period, now)

        if period != "yesterday" do
          assert DateTime.compare(to, now) == :gt,
                 "#{period} window ends before now, so today's traffic would be missing"
        end
      end
    end

    test "an unknown period falls back to the default rather than raising" do
      now = ~U[2026-03-10 09:00:00Z]

      assert Reports.period_range("nonsense", now) ==
               Reports.period_range(Reports.default_period(), now)

      assert Reports.period_range("", now) == Reports.period_range("7d", now)
    end
  end

  describe "bucket_for/1" do
    test "short windows chart hourly, long windows monthly" do
      assert Reports.bucket_for("today") == :hour
      assert Reports.bucket_for("yesterday") == :hour
      assert Reports.bucket_for("7d") == :day
      assert Reports.bucket_for("14d") == :day
      assert Reports.bucket_for("30d") == :day
      assert Reports.bucket_for("90d") == :day
      assert Reports.bucket_for("12m") == :month
      assert Reports.bucket_for("all") == :month
    end

    test "a filter is charted by its period, a custom range by its length" do
      now = ~U[2026-06-30 09:00:00Z]

      assert Reports.bucket_for(Reports.filter(period: "today", now: now)) == :hour
      assert Reports.bucket_for(Reports.filter(period: "12m", now: now)) == :month

      custom = &Reports.filter(period: "custom", from: &1, to: &2, now: now)

      assert Reports.bucket_for(custom.("2026-06-30", "2026-06-30")) == :day
      assert Reports.bucket_for(custom.("2026-03-31", "2026-06-30")) == :day
      assert Reports.bucket_for(custom.("2026-03-30", "2026-06-30")) == :month
    end
  end

  describe "filter/1" do
    test "carries the period label and normalizes blank restrictions" do
      filter = Reports.filter(period: "30d", site: "  ", path: "")

      assert filter.period == "30d"
      assert filter.site == nil
      assert filter.path == nil
    end

    test "a custom range covers both of its days, to the end of the last one" do
      filter =
        Reports.filter(
          period: "custom",
          from: "2026-03-01",
          to: ~D[2026-03-10],
          now: ~U[2026-04-01 09:00:00Z]
        )

      assert filter.period == "custom"
      assert filter.from == ~U[2026-03-01 00:00:00Z]
      assert filter.to == ~U[2026-03-11 00:00:00Z]
      assert Reports.filter_dates(filter) == {~D[2026-03-01], ~D[2026-03-10]}
    end

    test "a custom range of one day is that day" do
      filter =
        Reports.filter(
          period: "custom",
          from: "2026-03-10",
          to: "2026-03-10",
          now: ~U[2026-04-01 09:00:00Z]
        )

      assert DateTime.diff(filter.to, filter.from, :day) == 1
    end

    test "the days of a custom range are ignored under any other period" do
      now = ~U[2026-04-01 09:00:00Z]

      assert Reports.filter(period: "30d", from: "2026-01-01", to: "2026-01-02", now: now) ==
               Reports.filter(period: "30d", now: now)
    end

    test "defaults to the default period when none is given" do
      assert Reports.filter().period == Reports.default_period()
    end
  end

  describe "custom_range/3" do
    @today ~D[2026-04-01]

    test "a reversed pair is swapped" do
      assert Reports.custom_range("2026-03-10", "2026-03-01", @today) ==
               {~D[2026-03-01], ~D[2026-03-10]}
    end

    test "without days it is the week ending today" do
      assert Reports.custom_range(nil, nil, @today) == {~D[2026-03-26], @today}
      assert Reports.custom_range("", "nonsense", @today) == {~D[2026-03-26], @today}
    end

    test "a missing last day is today, a missing first day a week before the last" do
      assert Reports.custom_range("2026-02-01", nil, @today) == {~D[2026-02-01], @today}
      assert Reports.custom_range(nil, "2026-02-10", @today) == {~D[2026-02-04], ~D[2026-02-10]}
    end

    test "days are kept between 2000-01-01 and today" do
      assert Reports.custom_range("0001-01-01", "2999-12-31", @today) == {~D[2000-01-01], @today}
      assert Reports.custom_range("2999-01-01", "2999-12-31", @today) == {@today, @today}

      assert Reports.custom_range("1990-01-01", "1995-01-01", @today) ==
               {~D[2000-01-01], ~D[2000-01-01]}
    end
  end

  describe "periods/0 and period_label/1" do
    test "every period has a label, and labels round-trip" do
      for {value, label} <- Reports.periods() do
        assert Reports.period_label(value) == label
      end
    end

    test "an unknown value labels as itself rather than raising" do
      assert Reports.period_label("nonsense") == "nonsense"
    end
  end
end
