using System.Text.Json;
using MySqlConnector;

namespace StudyGo.GameServer.Marches;

public sealed record RecallResult(bool Success, string Status, DateTime? ReturnAtUtc = null);
public sealed record MissionCycleResult(int Settled, int Returned);

public sealed class MySqlMarchSettlementRepository
{
    private readonly string _connectionString;

    public MySqlMarchSettlementRepository(string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ArgumentException("A database connection string is required.", nameof(connectionString));
        _connectionString = connectionString;
    }

    public async Task<MissionCycleResult> RunCycleAsync(CancellationToken cancellationToken = default)
    {
        var settled = 0;
        var returned = 0;
        var due = new List<string>();

        await using (var db = new MySqlConnection(_connectionString))
        {
            await db.OpenAsync(cancellationToken);
            await using var cmd = new MySqlCommand(
                "SELECT march_id FROM player_marches WHERE march_state='arrived' OR (march_state='returning' AND return_at<=UTC_TIMESTAMP()) ORDER BY arrives_at LIMIT 100",
                db);
            await using var reader = await cmd.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
                due.Add(reader.GetString("march_id"));
        }

        foreach (var id in due)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var state = await ProcessOneAsync(id, cancellationToken);
            if (state == "settled") settled++;
            if (state == "returned") returned++;
        }
        return new(settled, returned);
    }

    private async Task<string?> ProcessOneAsync(string marchId, CancellationToken ct)
    {
        await using var db = new MySqlConnection(_connectionString);
        await db.OpenAsync(ct);
        await using var tx = await db.BeginTransactionAsync(ct);
        try
        {
            string serverId, destinationId, mission, state;
            long playerId;
            int travelSeconds;
            await using (var cmd = new MySqlCommand(
                "SELECT server_id,player_id,destination_object_id,mission_type,march_state,travel_seconds FROM player_marches WHERE march_id=@id FOR UPDATE",
                db, tx))
            {
                cmd.Parameters.AddWithValue("@id", marchId);
                await using var reader = await cmd.ExecuteReaderAsync(ct);
                if (!await reader.ReadAsync(ct))
                {
                    await tx.RollbackAsync(ct);
                    return null;
                }
                serverId = reader.GetString("server_id");
                playerId = reader.GetInt64("player_id");
                destinationId = reader.GetString("destination_object_id");
                mission = reader.GetString("mission_type");
                state = reader.GetString("march_state");
                travelSeconds = reader.GetInt32("travel_seconds");
            }

            if (state == "returning")
            {
                await ReleaseTroopsAsync(db, tx, marchId, ct);
                await using var finish = new MySqlCommand(
                    "UPDATE player_marches SET march_state='returned' WHERE march_id=@id AND march_state='returning' AND return_at<=UTC_TIMESTAMP()",
                    db, tx);
                finish.Parameters.AddWithValue("@id", marchId);
                var changed = await finish.ExecuteNonQueryAsync(ct);
                await tx.CommitAsync(ct);
                return changed == 1 ? "returned" : null;
            }

            if (state != "arrived")
            {
                await tx.RollbackAsync(ct);
                return null;
            }

            string resultJson;
            if (mission == "gather")
                resultJson = await SettleGatherAsync(db, tx, marchId, playerId, serverId, destinationId, ct);
            else if (mission == "hunt")
                resultJson = await SettleHuntAsync(db, tx, marchId, playerId, serverId, destinationId, ct);
            else if (mission == "scout")
                resultJson = await SettleScoutAsync(db, tx, marchId, playerId, serverId, destinationId, ct);
            else
                resultJson = JsonSerializer.Serialize(new { status = "unsupported_mission" });

            var returnAt = DateTime.UtcNow.AddSeconds(travelSeconds);
            await using (var update = new MySqlCommand(
                """
                UPDATE player_marches
                SET march_state='returning', mission_settled_at=UTC_TIMESTAMP(),
                    return_seconds=@seconds, return_at=@returnAt, result_json=@result
                WHERE march_id=@id AND march_state='arrived'
                """, db, tx))
            {
                update.Parameters.AddWithValue("@seconds", travelSeconds);
                update.Parameters.AddWithValue("@returnAt", returnAt);
                update.Parameters.AddWithValue("@result", resultJson);
                update.Parameters.AddWithValue("@id", marchId);
                if (await update.ExecuteNonQueryAsync(ct) != 1)
                    throw new InvalidOperationException("March state changed during settlement.");
            }

            await using (var log = new MySqlCommand(
                """
                INSERT INTO march_settlements (march_id,settlement_type,result_json,settled_at)
                VALUES (@id,@type,@result,UTC_TIMESTAMP())
                """, db, tx))
            {
                log.Parameters.AddWithValue("@id", marchId);
                log.Parameters.AddWithValue("@type", mission);
                log.Parameters.AddWithValue("@result", resultJson);
                await log.ExecuteNonQueryAsync(ct);
            }

            await tx.CommitAsync(ct);
            return "settled";
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }

    public async Task<RecallResult> RecallAsync(
        string serverId, long playerId, string marchId, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(serverId) || serverId.Length > 48 ||
            string.IsNullOrWhiteSpace(marchId) || marchId.Length > 80 || playerId <= 0)
            return new(false, "invalid_request");

        await using var db = new MySqlConnection(_connectionString);
        await db.OpenAsync(ct);
        await using var tx = await db.BeginTransactionAsync(ct);
        try
        {
            DateTime departed, arrives;
            int travelSeconds;
            string state;
            await using (var cmd = new MySqlCommand(
                """
                SELECT departed_at,arrives_at,travel_seconds,march_state
                FROM player_marches
                WHERE march_id=@id AND server_id=@server AND player_id=@player
                FOR UPDATE
                """, db, tx))
            {
                cmd.Parameters.AddWithValue("@id", marchId);
                cmd.Parameters.AddWithValue("@server", serverId);
                cmd.Parameters.AddWithValue("@player", playerId);
                await using var reader = await cmd.ExecuteReaderAsync(ct);
                if (!await reader.ReadAsync(ct))
                {
                    await tx.RollbackAsync(ct);
                    return new(false, "march_not_found");
                }
                departed = DateTime.SpecifyKind(reader.GetDateTime("departed_at"), DateTimeKind.Utc);
                arrives = DateTime.SpecifyKind(reader.GetDateTime("arrives_at"), DateTimeKind.Utc);
                travelSeconds = reader.GetInt32("travel_seconds");
                state = reader.GetString("march_state");
            }

            if (state is not ("traveling" or "arrived"))
            {
                await tx.RollbackAsync(ct);
                return new(false, "march_not_recallable");
            }

            var now = DateTime.UtcNow;
            var returnSeconds = state == "arrived"
                ? travelSeconds
                : Math.Clamp((int)Math.Ceiling((now - departed).TotalSeconds), 10, travelSeconds);
            var returnAt = now.AddSeconds(returnSeconds);
            var result = JsonSerializer.Serialize(new { status = "recalled", reason = "player_recall" });

            await using (var update = new MySqlCommand(
                """
                UPDATE player_marches
                SET march_state='returning', recall_requested_at=UTC_TIMESTAMP(),
                    mission_settled_at=UTC_TIMESTAMP(), return_seconds=@seconds,
                    return_at=@returnAt, result_json=@result
                WHERE march_id=@id AND server_id=@server AND player_id=@player
                  AND march_state IN ('traveling','arrived')
                """, db, tx))
            {
                update.Parameters.AddWithValue("@seconds", returnSeconds);
                update.Parameters.AddWithValue("@returnAt", returnAt);
                update.Parameters.AddWithValue("@result", result);
                update.Parameters.AddWithValue("@id", marchId);
                update.Parameters.AddWithValue("@server", serverId);
                update.Parameters.AddWithValue("@player", playerId);
                if (await update.ExecuteNonQueryAsync(ct) != 1)
                {
                    await tx.RollbackAsync(ct);
                    return new(false, "march_state_changed");
                }
            }

            await using (var log = new MySqlCommand(
                """
                INSERT INTO march_settlements (march_id,settlement_type,result_json,settled_at)
                VALUES (@id,'recall',@result,UTC_TIMESTAMP())
                ON DUPLICATE KEY UPDATE march_id=march_id
                """, db, tx))
            {
                log.Parameters.AddWithValue("@id", marchId);
                log.Parameters.AddWithValue("@result", result);
                await log.ExecuteNonQueryAsync(ct);
            }

            await tx.CommitAsync(ct);
            return new(true, "recalling", returnAt);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }

    private static async Task<string> SettleGatherAsync(
        MySqlConnection db, MySqlTransaction tx, string marchId, long playerId,
        string serverId, string objectId, CancellationToken ct)
    {
        long remaining;
        string? objectData;
        string instanceState;
        int respawnSeconds;
        await using (var cmd = new MySqlCommand(
            """
            SELECT o.remaining_capacity,CAST(o.object_data AS CHAR) AS object_data,
                   i.instance_state,t.respawn_seconds
            FROM world_map_objects o
            INNER JOIN world_spawn_instances i ON i.object_id=o.object_id
            INNER JOIN world_spawn_templates t ON t.id=i.template_id
            WHERE o.object_id=@id AND o.server_id=@server FOR UPDATE
            """, db, tx))
        {
            cmd.Parameters.AddWithValue("@id", objectId);
            cmd.Parameters.AddWithValue("@server", serverId);
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct) || reader.IsDBNull(reader.GetOrdinal("remaining_capacity")))
                return JsonSerializer.Serialize(new { status = "resource_unavailable", amount = 0 });
            remaining = reader.GetInt64("remaining_capacity");
            objectData = reader.IsDBNull(reader.GetOrdinal("object_data")) ? null : reader.GetString("object_data");
            instanceState = reader.GetString("instance_state");
            respawnSeconds = reader.GetInt32("respawn_seconds");
        }
        if (instanceState != "alive" || remaining <= 0)
            return JsonSerializer.Serialize(new { status = "resource_depleted", amount = 0 });

        long carry = await GetCarryCapacityAsync(db, tx, marchId, ct);
        long amount = Math.Min(remaining, carry);
        if (amount <= 0)
            return JsonSerializer.Serialize(new { status = "no_carry_capacity", amount = 0 });

        string resourceCode = ReadString(objectData, "resourceCode") ?? "wood";
        await using (var update = new MySqlCommand(
            "UPDATE world_map_objects SET remaining_capacity=remaining_capacity-@amount WHERE object_id=@id AND remaining_capacity>=@amount",
            db, tx))
        {
            update.Parameters.AddWithValue("@amount", amount);
            update.Parameters.AddWithValue("@id", objectId);
            if (await update.ExecuteNonQueryAsync(ct) != 1)
                throw new InvalidOperationException("Resource capacity changed during settlement.");
        }
        await AddResourceAsync(db, tx, playerId, serverId, resourceCode, amount, ct);
        await DepleteIfEmptyAsync(db, tx, objectId, respawnSeconds, ct);
        return JsonSerializer.Serialize(new { status = "success", resourceCode, amount });
    }

    private static async Task<string> SettleHuntAsync(
        MySqlConnection db, MySqlTransaction tx, string marchId, long playerId,
        string serverId, string objectId, CancellationToken ct)
    {
        long hp;
        string? data;
        string instanceState;
        int respawnSeconds;
        await using (var cmd = new MySqlCommand(
            """
            SELECT o.remaining_capacity,CAST(o.object_data AS CHAR) AS object_data,
                   i.instance_state,t.respawn_seconds
            FROM world_map_objects o
            INNER JOIN world_spawn_instances i ON i.object_id=o.object_id
            INNER JOIN world_spawn_templates t ON t.id=i.template_id
            WHERE o.object_id=@id AND o.server_id=@server FOR UPDATE
            """, db, tx))
        {
            cmd.Parameters.AddWithValue("@id", objectId);
            cmd.Parameters.AddWithValue("@server", serverId);
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct) || reader.IsDBNull(reader.GetOrdinal("remaining_capacity")))
                return JsonSerializer.Serialize(new { status = "monster_unavailable", damage = 0 });
            hp = reader.GetInt64("remaining_capacity");
            data = reader.IsDBNull(reader.GetOrdinal("object_data")) ? null : reader.GetString("object_data");
            instanceState = reader.GetString("instance_state");
            respawnSeconds = reader.GetInt32("respawn_seconds");
        }
        if (instanceState != "alive" || hp <= 0)
            return JsonSerializer.Serialize(new { status = "monster_already_defeated", damage = 0 });

        long power = await GetHuntPowerAsync(db, tx, marchId, ct);
        long damage = Math.Min(hp, power);
        long remainingHp = hp - damage;
        await using (var update = new MySqlCommand(
            "UPDATE world_map_objects SET remaining_capacity=@hp WHERE object_id=@id",
            db, tx))
        {
            update.Parameters.AddWithValue("@hp", remainingHp);
            update.Parameters.AddWithValue("@id", objectId);
            await update.ExecuteNonQueryAsync(ct);
        }

        var drops = new Dictionary<string, long>();
        var defeated = remainingHp == 0;
        if (defeated)
        {
            drops = ReadDrops(data);
            foreach (var drop in drops)
                await AddResourceAsync(db, tx, playerId, serverId, drop.Key, drop.Value, ct);
            await using var mark = new MySqlCommand(
                """
                UPDATE world_spawn_instances SET instance_state='defeated',
                    respawn_at=DATE_ADD(UTC_TIMESTAMP(), INTERVAL @seconds SECOND)
                WHERE object_id=@id AND instance_state='alive';
                """, db, tx);
            mark.Parameters.AddWithValue("@seconds", respawnSeconds);
            mark.Parameters.AddWithValue("@id", objectId);
            await mark.ExecuteNonQueryAsync(ct);
            await using var obj = new MySqlCommand(
                "UPDATE world_map_objects SET object_status='defeated' WHERE object_id=@id",
                db, tx);
            obj.Parameters.AddWithValue("@id", objectId);
            await obj.ExecuteNonQueryAsync(ct);
        }
        return JsonSerializer.Serialize(new { status = defeated ? "victory" : "monster_survived", damage, remainingHp, drops });
    }

    private static async Task<string> SettleScoutAsync(
        MySqlConnection db, MySqlTransaction tx, string marchId, long playerId,
        string serverId, string objectId, CancellationToken ct)
    {
        string report;
        await using (var cmd = new MySqlCommand(
            """
            SELECT o.object_id,o.object_type,o.display_name,o.object_level,
                   o.coordinate_x,o.coordinate_y,o.object_status,o.remaining_capacity,
                   CAST(o.object_data AS CHAR) AS object_data,
                   c.castle_level
            FROM world_map_objects o
            LEFT JOIN player_castles c ON c.map_object_id=o.object_id
            WHERE o.object_id=@id AND o.server_id=@server
            FOR UPDATE
            """, db, tx))
        {
            cmd.Parameters.AddWithValue("@id", objectId);
            cmd.Parameters.AddWithValue("@server", serverId);
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct))
                return JsonSerializer.Serialize(new { status = "target_missing" });
            var payload = new
            {
                objectId = reader.GetString("object_id"),
                type = reader.GetString("object_type"),
                name = reader.GetString("display_name"),
                level = reader.GetInt32("object_level"),
                x = reader.GetInt32("coordinate_x"),
                y = reader.GetInt32("coordinate_y"),
                status = reader.GetString("object_status"),
                remainingCapacity = reader.IsDBNull(reader.GetOrdinal("remaining_capacity")) ? (long?)null : reader.GetInt64("remaining_capacity"),
                castleLevel = reader.IsDBNull(reader.GetOrdinal("castle_level")) ? (int?)null : reader.GetInt32("castle_level"),
                data = reader.IsDBNull(reader.GetOrdinal("object_data")) ? null : reader.GetString("object_data")
            };
            report = JsonSerializer.Serialize(payload);
        }
        await using var save = new MySqlCommand(
            """
            INSERT INTO march_scout_reports
                (march_id,server_id,player_id,target_object_id,report_json,expires_at)
            VALUES (@march,@server,@player,@target,@report,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 24 HOUR))
            """, db, tx);
        save.Parameters.AddWithValue("@march", marchId);
        save.Parameters.AddWithValue("@server", serverId);
        save.Parameters.AddWithValue("@player", playerId);
        save.Parameters.AddWithValue("@target", objectId);
        save.Parameters.AddWithValue("@report", report);
        await save.ExecuteNonQueryAsync(ct);
        return JsonSerializer.Serialize(new { status = "scouted", report });
    }

    private static async Task<long> GetCarryCapacityAsync(MySqlConnection db, MySqlTransaction tx, string marchId, CancellationToken ct)
    {
        await using var cmd = new MySqlCommand(
            """
            SELECT COALESCE(SUM(a.quantity*d.carry_capacity),0)
            FROM march_troop_assignments a
            INNER JOIN troop_definitions d ON d.troop_code=a.troop_code
            WHERE a.march_id=@id
            """, db, tx);
        cmd.Parameters.AddWithValue("@id", marchId);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
    }

    private static async Task<long> GetHuntPowerAsync(MySqlConnection db, MySqlTransaction tx, string marchId, CancellationToken ct)
    {
        await using var cmd = new MySqlCommand(
            """
            SELECT COALESCE(SUM(a.quantity * CASE d.troop_type
                WHEN 'infantry' THEN 10 WHEN 'archer' THEN 12 WHEN 'cavalry' THEN 14
                WHEN 'mage' THEN 16 WHEN 'support' THEN 5 WHEN 'siege' THEN 18 ELSE 5 END),0)
            FROM march_troop_assignments a
            INNER JOIN troop_definitions d ON d.troop_code=a.troop_code
            WHERE a.march_id=@id
            """, db, tx);
        cmd.Parameters.AddWithValue("@id", marchId);
        return Convert.ToInt64(await cmd.ExecuteScalarAsync(ct));
    }

    private static async Task AddResourceAsync(MySqlConnection db, MySqlTransaction tx, long playerId,
        string serverId, string code, long amount, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(code) || code.Length > 48 ||
            code.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '_' and not '-'))
            throw new InvalidOperationException("Invalid resource code in world content configuration.");
        await using var cmd = new MySqlCommand(
            """
            INSERT INTO player_resources (player_id,server_id,resource_code,quantity)
            VALUES (@player,@server,@code,@amount)
            ON DUPLICATE KEY UPDATE quantity=quantity+VALUES(quantity)
            """, db, tx);
        cmd.Parameters.AddWithValue("@player", playerId);
        cmd.Parameters.AddWithValue("@server", serverId);
        cmd.Parameters.AddWithValue("@code", code);
        cmd.Parameters.AddWithValue("@amount", amount);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task DepleteIfEmptyAsync(MySqlConnection db, MySqlTransaction tx,
        string objectId, int respawnSeconds, CancellationToken ct)
    {
        await using var cmd = new MySqlCommand(
            """
            UPDATE world_map_objects o
            INNER JOIN world_spawn_instances i ON i.object_id=o.object_id
            SET o.object_status='depleted',
                i.instance_state='depleted',
                i.respawn_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL @seconds SECOND)
            WHERE o.object_id=@id AND o.remaining_capacity<=0 AND i.instance_state='alive'
            """, db, tx);
        cmd.Parameters.AddWithValue("@seconds", respawnSeconds);
        cmd.Parameters.AddWithValue("@id", objectId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task ReleaseTroopsAsync(MySqlConnection db, MySqlTransaction tx, string marchId, CancellationToken ct)
    {
        await using var cmd = new MySqlCommand(
            """
            UPDATE player_troops pt
            INNER JOIN march_troop_assignments a ON a.troop_code=pt.troop_code
            INNER JOIN player_marches m ON m.march_id=a.march_id
            SET pt.reserved_quantity=GREATEST(0,pt.reserved_quantity-a.quantity)
            WHERE a.march_id=@id AND pt.player_id=m.player_id AND pt.server_id=m.server_id
            """, db, tx);
        cmd.Parameters.AddWithValue("@id", marchId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static string? ReadString(string? json, string property)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString() : null;
        }
        catch (JsonException) { return null; }
    }

    private static Dictionary<string, long> ReadDrops(string? json)
    {
        var drops = new Dictionary<string, long>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(json)) return drops;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("drops", out var array) || array.ValueKind != JsonValueKind.Array)
                return drops;
            foreach (var item in array.EnumerateArray())
            {
                if (!item.TryGetProperty("resourceCode", out var codeNode) || codeNode.ValueKind != JsonValueKind.String)
                    continue;
                var code = codeNode.GetString();
                if (string.IsNullOrWhiteSpace(code) || code.Length > 48 ||
                    code.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '_' and not '-'))
                    continue;
                var min = item.TryGetProperty("min", out var minNode) && minNode.TryGetInt64(out var minValue) ? minValue : 1;
                var max = item.TryGetProperty("max", out var maxNode) && maxNode.TryGetInt64(out var maxValue) ? maxValue : min;
                if (min < 0 || max < min || max > 1000000) continue;
                var amount = min == max ? min : Random.Shared.NextInt64(min, max + 1);
                if (amount > 0) drops[code] = drops.GetValueOrDefault(code) + amount;
            }
        }
        catch (JsonException) { }
        return drops;
    }
}
