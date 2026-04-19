using STS2Mobile.Steam;
using Xunit;

namespace STS2Mobile.Tests;

public class SaveProgressComparerTests
{
    // --- progress*.save files: cascade through progress indicators -----------

    [Fact]
    public void FloorsClimbed_higher_wins()
    {
        var local = "{\"floors_climbed\": 42}";
        var cloud = "{\"floors_climbed\": 10}";

        Assert.Equal(
            CompareResult.LocalWins,
            SaveProgressComparer.Compare("user://profile0/progress.save", local, cloud)
        );
    }

    [Fact]
    public void FloorsClimbed_lower_loses()
    {
        var local = "{\"floors_climbed\": 5}";
        var cloud = "{\"floors_climbed\": 50}";

        Assert.Equal(
            CompareResult.CloudWins,
            SaveProgressComparer.Compare("user://profile0/progress.save", local, cloud)
        );
    }

    [Fact]
    public void TotalGames_is_tiebreaker_when_floors_equal()
    {
        var local = Json(floors: 10, wins: 3, losses: 2);
        var cloud = Json(floors: 10, wins: 1, losses: 1);

        Assert.Equal(
            CompareResult.LocalWins,
            SaveProgressComparer.Compare("user://profile0/progress.save", local, cloud)
        );
    }

    [Fact]
    public void Discovered_is_tiebreaker_when_games_equal()
    {
        var local = Json(floors: 10, wins: 2, losses: 2, discoveredCards: 8);
        var cloud = Json(floors: 10, wins: 2, losses: 2, discoveredCards: 3);

        Assert.Equal(
            CompareResult.LocalWins,
            SaveProgressComparer.Compare("user://profile0/progress.save", local, cloud)
        );
    }

    [Fact]
    public void Playtime_is_last_tiebreaker()
    {
        var local = Json(floors: 10, wins: 2, losses: 2, discoveredCards: 3, playtime: 900);
        var cloud = Json(floors: 10, wins: 2, losses: 2, discoveredCards: 3, playtime: 600);

        Assert.Equal(
            CompareResult.LocalWins,
            SaveProgressComparer.Compare("user://profile0/progress.save", local, cloud)
        );
    }

    [Fact]
    public void Equal_progress_returns_equal()
    {
        var content = Json(floors: 10, wins: 1, losses: 1, discoveredCards: 3, playtime: 600);

        Assert.Equal(
            CompareResult.Equal,
            SaveProgressComparer.Compare("user://profile0/progress.save", content, content)
        );
    }

    // --- non-progress files default to Equal -------------------------------

    [Fact]
    public void Non_progress_file_returns_equal()
    {
        Assert.Equal(
            CompareResult.Equal,
            SaveProgressComparer.Compare("user://profile0/prefs.save", "{}", "{}")
        );
    }

    // --- current_run*.save: floors counted from map_point_history ---------

    [Fact]
    public void CurrentRun_higher_map_points_wins()
    {
        var local = "{\"map_point_history\": [[0,1],[2,3,4]]}"; // 5 floors
        var cloud = "{\"map_point_history\": [[0],[1,2]]}";     // 3 floors

        Assert.Equal(
            CompareResult.LocalWins,
            SaveProgressComparer.Compare("user://profile0/current_run.save", local, cloud)
        );
    }

    [Fact]
    public void CurrentRun_alternate_format_uses_acts_length()
    {
        var local = "{\"acts\": [1,2,3]}"; // 3 floors
        var cloud = "{\"acts\": [1]}";     // 1 floor

        Assert.Equal(
            CompareResult.LocalWins,
            SaveProgressComparer.Compare("user://profile0/current_run.save", local, cloud)
        );
    }

    [Fact]
    public void CurrentRun_equal_floors_returns_equal()
    {
        var content = "{\"map_point_history\": [[0,1],[2]]}";

        Assert.Equal(
            CompareResult.Equal,
            SaveProgressComparer.Compare("user://profile0/current_run.save", content, content)
        );
    }

    // --- malformed JSON falls back to Equal ---------------------------------

    [Fact]
    public void Malformed_json_returns_equal()
    {
        Assert.Equal(
            CompareResult.Equal,
            SaveProgressComparer.Compare("user://profile0/progress.save", "{not json", "{}")
        );
    }

    // --- helpers ------------------------------------------------------------

    private static string Json(
        int floors = 0,
        int wins = 0,
        int losses = 0,
        int discoveredCards = 0,
        int playtime = 0
    )
    {
        return $$"""
        {
          "floors_climbed": {{floors}},
          "total_playtime": {{playtime}},
          "character_stats": [
            { "total_wins": {{wins}}, "total_losses": {{losses}} }
          ],
          "discovered_cards": [{{string.Join(",", new int[discoveredCards])}}]
        }
        """;
    }
}
