require "test_helper"

# Pure-function tests for the aggregation and similarity maths (no network).
# Direct port of backend/tests/test_metrics.py so both backends are held to the
# same expectations.
class MetricsTest < ActiveSupport::TestCase
  def make_profile(player_id, group, minutes, competition_id: 1, **totals)
    values = CoachAnalyst::Aggregate.empty_totals(minutes)
    totals.each { |key, value| values[key.to_s] = value }
    {
      "playerID" => player_id,
      "name" => player_id,
      "teamName" => "Team",
      "competitionID" => competition_id,
      "competitionName" => "Comp #{competition_id}",
      "group" => group,
      "primaryPosition" => "X",
      "totals" => values
    }
  end

  def test_metric_value_is_per_90
    totals = CoachAnalyst::Aggregate.empty_totals(90)
    totals["goals"] = 3
    assert_equal 3.0, CoachAnalyst::Metrics.metric_value("goals", totals, 90)
    assert_equal 6.0, CoachAnalyst::Metrics.metric_value("goals", totals, 45)
  end

  def test_pass_accuracy_is_a_ratio
    totals = { "passesAttempted" => 10, "passesCompleted" => 5 }
    assert_equal 0.5, CoachAnalyst::Metrics.metric_value("passAccuracy", totals, 90)
    assert_equal 0.0, CoachAnalyst::Metrics.metric_value("passAccuracy", { "passesAttempted" => 0 }, 90)
  end

  def test_similar_respects_group_and_competition
    target = make_profile("p1", "Midfielder", 900, competition_id: 1,
                          passesAttempted: 900, passesCompleted: 810, progressivePasses: 120)
    pool = [
      target,
      make_profile("same_comp", "Midfielder", 900, competition_id: 1,
                   passesAttempted: 880, passesCompleted: 800, progressivePasses: 110),
      make_profile("other_comp", "Midfielder", 900, competition_id: 2,
                   passesAttempted: 870, passesCompleted: 790, progressivePasses: 115),
      make_profile("wrong_group", "Defender", 900, competition_id: 2, tacklesWon: 50)
    ]
    result = CoachAnalyst::Metrics.similar(target, pool, other_competitions_only: true, min_minutes: 0)
    ids = result["similar"].map { |item| item["profile"]["playerID"] }
    assert_includes ids, "other_comp"
    refute_includes ids, "same_comp" # same competition excluded
    refute_includes ids, "wrong_group" # different role excluded
  end

  def test_comparison_normalises_to_percentiles
    target = make_profile("t", "Forward", 900, goals: 20, shots: 80)
    candidate = make_profile("c", "Forward", 900, goals: 4, shots: 30)
    pool = (1..10).map { |i| make_profile("p#{i}", "Forward", 900, goals: i, shots: i * 3) }
    rows = CoachAnalyst::Metrics.comparison(target, candidate, pool, min_minutes: 0)
    goals = rows.find { |row| row["metric"] == "goals" }
    assert goals["targetNormalized"] >= goals["candidateNormalized"]
  end

  def test_contributions_from_synthetic_events
    lineups = [{
      "team_id" => 1, "team_name" => "A",
      "lineup" => [{
        "player_id" => 10, "player_name" => "P", "player_nickname" => nil,
        "positions" => [{ "position" => "Center Forward", "from" => "00:00", "to" => nil }]
      }]
    }]
    events = [
      { "id" => "e1", "minute" => 40, "type" => { "name" => "Shot" }, "team" => { "id" => 1, "name" => "A" },
        "player" => { "id" => 10, "name" => "P" }, "location" => [110, 40],
        "shot" => { "statsbomb_xg" => 0.5, "outcome" => { "name" => "Goal" } } },
      { "id" => "e2", "minute" => 90, "type" => { "name" => "Pass" }, "team" => { "id" => 1, "name" => "A" },
        "player" => { "id" => 10, "name" => "P" }, "location" => [50, 40],
        "pass" => { "end_location" => [70, 40] } }
    ]
    output = CoachAnalyst::Aggregate.contributions(events, lineups)
    assert_equal 1, output.length
    player = output.first
    assert_equal 90, player["minutes"]
    assert_equal "Forward", player["group"]
    assert_equal 1, player["totals"]["goals"]
    assert_equal 0.5, player["totals"]["xg"]
    assert_equal 1, player["totals"]["touchesInBox"]
    assert_equal 1, player["totals"]["passesAttempted"]
    assert_equal 1, player["totals"]["passesCompleted"]
    assert_equal 1, player["totals"]["progressivePasses"]
  end
end
