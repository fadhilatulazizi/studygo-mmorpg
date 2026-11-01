using MySqlConnector;

namespace StudyGo.GameServer.Marches;

public sealed record MarchListItem(string MarchId,string MissionType,string State,string DestinationObjectId,
    int OriginX,int OriginY,int DestinationX,int DestinationY,DateTime DepartedAtUtc,DateTime ArrivesAtUtc,
    DateTime? ReturnAtUtc,string? ResultJson);

public sealed class MySqlMarchApiRepository
{
    private readonly string _connectionString;
    public MySqlMarchApiRepository(string connectionString) => _connectionString=connectionString;

    public async Task<long?> ResolvePlayerIdAsync(long studyGoUserId,CancellationToken ct)
    {
        await using var db=new MySqlConnection(_connectionString);
        await db.OpenAsync(ct);
        await using var cmd=new MySqlCommand("SELECT id FROM game_players WHERE studygo_user_id=@user LIMIT 1",db);
        cmd.Parameters.AddWithValue("@user",studyGoUserId);
        var value=await cmd.ExecuteScalarAsync(ct);
        return value is null or DBNull ? null : Convert.ToInt64(value);
    }

    public async Task<IReadOnlyList<MarchListItem>> GetPlayerMarchesAsync(string serverId,long playerId,bool includeReturned,CancellationToken ct)
    {
        var rows=new List<MarchListItem>();
        await using var db=new MySqlConnection(_connectionString);
        await db.OpenAsync(ct);
        await using var cmd=new MySqlCommand("""
            SELECT march_id,mission_type,march_state,destination_object_id,origin_x,origin_y,
                   destination_x,destination_y,departed_at,arrives_at,return_at,
                   CAST(result_json AS CHAR) AS result_json
            FROM player_marches
            WHERE server_id=@server AND player_id=@player
              AND (@includeReturned=1 OR march_state NOT IN ('returned','cancelled','failed'))
            ORDER BY created_at DESC LIMIT 100
            """,db);
        cmd.Parameters.AddWithValue("@server",serverId);
        cmd.Parameters.AddWithValue("@player",playerId);
        cmd.Parameters.AddWithValue("@includeReturned",includeReturned?1:0);
        await using var reader=await cmd.ExecuteReaderAsync(ct);
        while(await reader.ReadAsync(ct))
            rows.Add(new MarchListItem(reader.GetString("march_id"),reader.GetString("mission_type"),
                reader.GetString("march_state"),reader.GetString("destination_object_id"),
                reader.GetInt32("origin_x"),reader.GetInt32("origin_y"),reader.GetInt32("destination_x"),
                reader.GetInt32("destination_y"),DateTime.SpecifyKind(reader.GetDateTime("departed_at"),DateTimeKind.Utc),
                DateTime.SpecifyKind(reader.GetDateTime("arrives_at"),DateTimeKind.Utc),
                reader.IsDBNull(reader.GetOrdinal("return_at"))?null:DateTime.SpecifyKind(reader.GetDateTime("return_at"),DateTimeKind.Utc),
                reader.IsDBNull(reader.GetOrdinal("result_json"))?null:reader.GetString("result_json")));
        return rows;
    }

    public async Task<string?> GetScoutReportAsync(string serverId,long playerId,string marchId,CancellationToken ct)
    {
        await using var db=new MySqlConnection(_connectionString);
        await db.OpenAsync(ct);
        await using var cmd=new MySqlCommand("""
            SELECT CAST(report_json AS CHAR) FROM march_scout_reports
            WHERE server_id=@server AND player_id=@player AND march_id=@march
              AND (expires_at IS NULL OR expires_at>UTC_TIMESTAMP()) LIMIT 1
            """,db);
        cmd.Parameters.AddWithValue("@server",serverId);
        cmd.Parameters.AddWithValue("@player",playerId);
        cmd.Parameters.AddWithValue("@march",marchId);
        var value=await cmd.ExecuteScalarAsync(ct);
        return value is null or DBNull?null:Convert.ToString(value);
    }
}