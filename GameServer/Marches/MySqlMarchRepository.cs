using MySqlConnector;

namespace StudyGo.GameServer.Marches;

public sealed record MarchTroopRequest(string TroopCode, long Quantity);

public sealed record MarchSendResult(
    bool Success,
    string Status,
    string? MarchId = null,
    DateTime? ArrivesAtUtc = null,
    int? TravelSeconds = null);

public sealed class MySqlMarchRepository
{
    private readonly string _connectionString;

    public MySqlMarchRepository(string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ArgumentException("A database connection string is required.", nameof(connectionString));
        _connectionString = connectionString;
    }

    public async Task<MarchSendResult> SendAsync(
        string serverId,
        long playerId,
        string requestId,
        string destinationObjectId,
        string missionType,
        IReadOnlyCollection<MarchTroopRequest> troops,
        CancellationToken cancellationToken = default)
    {
        ValidateId(serverId, 48, nameof(serverId));
        ValidateId(requestId, 80, nameof(requestId));
        ValidateId(destinationObjectId, 80, nameof(destinationObjectId));
        if (playerId <= 0) throw new ArgumentOutOfRangeException(nameof(playerId));
        if (missionType is not ("gather" or "hunt" or "scout" or "attack"))
            return new(false, "invalid_mission");
        if (troops.Count == 0 || troops.Count > 6 ||
            troops.Any(t => string.IsNullOrWhiteSpace(t.TroopCode) || t.TroopCode.Length > 48 || t.Quantity <= 0) ||
            troops.Select(t => t.TroopCode).Distinct(StringComparer.Ordinal).Count() != troops.Count)
            return new(false, "invalid_troop_composition");

        await using var db = new MySqlConnection(_connectionString);
        await db.OpenAsync(cancellationToken);
        await using var tx = await db.BeginTransactionAsync(cancellationToken);
        try
        {
            // Idempotency: a retried client request returns the original march.
            await using (var existing = new MySqlCommand(
                "SELECT march_id, arrives_at, travel_seconds FROM player_marches WHERE player_id=@player AND server_id=@server AND request_id=@request LIMIT 1",
                db, tx))
            {
                existing.Parameters.AddWithValue("@player", playerId);
                existing.Parameters.AddWithValue("@server", serverId);
                existing.Parameters.AddWithValue("@request", requestId);
                await using var reader = await existing.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    var result = new MarchSendResult(true, "already_created",
                        reader.GetString("march_id"), DateTime.SpecifyKind(reader.GetDateTime("arrives_at"), DateTimeKind.Utc),
                        reader.GetInt32("travel_seconds"));
                    await reader.CloseAsync();
                    await tx.CommitAsync(cancellationToken);
                    return result;
                }
            }

            int ox, oy, dx, dy;
            string originId;
            await using (var command = new MySqlCommand(
                """
                SELECT c.map_object_id, o.coordinate_x, o.coordinate_y
                FROM player_castles c
                INNER JOIN world_map_objects o ON o.object_id=c.map_object_id
                WHERE c.server_id=@server AND c.player_id=@player AND o.object_status='active'
                FOR UPDATE
                """, db, tx))
            {
                command.Parameters.AddWithValue("@server", serverId);
                command.Parameters.AddWithValue("@player", playerId);
                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    await tx.RollbackAsync(cancellationToken);
                    return new(false, "castle_not_found");
                }
                originId = reader.GetString("map_object_id");
                ox = reader.GetInt32("coordinate_x");
                oy = reader.GetInt32("coordinate_y");
            }

            string destinationType;
            string destinationStatus;
            await using (var command = new MySqlCommand(
                """
                SELECT coordinate_x, coordinate_y, object_type, object_status
                FROM world_map_objects
                WHERE object_id=@object AND server_id=@server
                FOR UPDATE
                """, db, tx))
            {
                command.Parameters.AddWithValue("@object", destinationObjectId);
                command.Parameters.AddWithValue("@server", serverId);
                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    await tx.RollbackAsync(cancellationToken);
                    return new(false, "destination_not_found");
                }
                dx = reader.GetInt32("coordinate_x");
                dy = reader.GetInt32("coordinate_y");
                destinationType = reader.GetString("object_type");
                destinationStatus = reader.GetString("object_status");
            }

            if (destinationStatus != "active" || destinationObjectId == originId)
            {
                await tx.RollbackAsync(cancellationToken);
                return new(false, "destination_unavailable");
            }
            if ((missionType == "gather" && destinationType != "resource") ||
                (missionType == "hunt" && destinationType != "monster") ||
                (missionType == "attack" && destinationType is not ("castle" or "guild_building")))
            {
                await tx.RollbackAsync(cancellationToken);
                return new(false, "mission_target_mismatch");
            }
            if (missionType == "attack")
            {
                await tx.RollbackAsync(cancellationToken);
                return new(false, "pvp_resolution_not_enabled");
            }

            double distance = Math.Sqrt(Math.Pow(dx - ox, 2) + Math.Pow(dy - oy, 2));
            decimal slowestSpeed = decimal.MaxValue;
            foreach (var troop in troops)
            {
                await using var reserve = new MySqlCommand(
                    """
                    SELECT pt.quantity, pt.reserved_quantity, td.march_speed
                    FROM player_troops pt
                    INNER JOIN troop_definitions td ON td.troop_code=pt.troop_code AND td.is_enabled=1
                    WHERE pt.player_id=@player AND pt.server_id=@server AND pt.troop_code=@code
                    FOR UPDATE
                    """, db, tx);
                reserve.Parameters.AddWithValue("@player", playerId);
                reserve.Parameters.AddWithValue("@server", serverId);
                reserve.Parameters.AddWithValue("@code", troop.TroopCode);
                await using var reader = await reserve.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    await tx.RollbackAsync(cancellationToken);
                    return new(false, "troop_not_available");
                }
                long available = reader.GetInt64("quantity") - reader.GetInt64("reserved_quantity");
                decimal speed = reader.GetDecimal("march_speed");
                await reader.CloseAsync();
                if (available < troop.Quantity)
                {
                    await tx.RollbackAsync(cancellationToken);
                    return new(false, "insufficient_troops");
                }
                if (speed < slowestSpeed) slowestSpeed = speed;
            }

            int travelSeconds = Math.Clamp((int)Math.Ceiling(distance * 60d / (double)slowestSpeed), 10, 86400);
            var marchId = $"march-{Guid.NewGuid():N}";
            var now = DateTime.UtcNow;
            var arrives = now.AddSeconds(travelSeconds);

            await using (var insert = new MySqlCommand(
                """
                INSERT INTO player_marches
                    (march_id, request_id, server_id, player_id, origin_castle_id, destination_object_id,
                     mission_type, march_state, origin_x, origin_y, destination_x, destination_y,
                     travel_seconds, departed_at, arrives_at)
                VALUES
                    (@id,@request,@server,@player,@origin,@destination,@mission,'traveling',
                     @ox,@oy,@dx,@dy,@seconds,@departed,@arrives)
                """, db, tx))
            {
                insert.Parameters.AddWithValue("@id", marchId);
                insert.Parameters.AddWithValue("@request", requestId);
                insert.Parameters.AddWithValue("@server", serverId);
                insert.Parameters.AddWithValue("@player", playerId);
                insert.Parameters.AddWithValue("@origin", originId);
                insert.Parameters.AddWithValue("@destination", destinationObjectId);
                insert.Parameters.AddWithValue("@mission", missionType);
                insert.Parameters.AddWithValue("@ox", ox);
                insert.Parameters.AddWithValue("@oy", oy);
                insert.Parameters.AddWithValue("@dx", dx);
                insert.Parameters.AddWithValue("@dy", dy);
                insert.Parameters.AddWithValue("@seconds", travelSeconds);
                insert.Parameters.AddWithValue("@departed", now);
                insert.Parameters.AddWithValue("@arrives", arrives);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }

            foreach (var troop in troops)
            {
                await using var reserve = new MySqlCommand(
                    """
                    UPDATE player_troops SET reserved_quantity=reserved_quantity+@qty
                    WHERE player_id=@player AND server_id=@server AND troop_code=@code
                      AND quantity-reserved_quantity>=@qty
                    """, db, tx);
                reserve.Parameters.AddWithValue("@qty", troop.Quantity);
                reserve.Parameters.AddWithValue("@player", playerId);
                reserve.Parameters.AddWithValue("@server", serverId);
                reserve.Parameters.AddWithValue("@code", troop.TroopCode);
                if (await reserve.ExecuteNonQueryAsync(cancellationToken) != 1)
                    throw new InvalidOperationException("Troop reservation changed during march creation.");
                await using var assignment = new MySqlCommand(
                    "INSERT INTO march_troop_assignments (march_id,troop_code,quantity) VALUES (@march,@code,@qty)",
                    db, tx);
                assignment.Parameters.AddWithValue("@march", marchId);
                assignment.Parameters.AddWithValue("@code", troop.TroopCode);
                assignment.Parameters.AddWithValue("@qty", troop.Quantity);
                await assignment.ExecuteNonQueryAsync(cancellationToken);
            }

            await tx.CommitAsync(cancellationToken);
            return new(true, "created", marchId, arrives, travelSeconds);
        }
        catch
        {
            await tx.RollbackAsync(cancellationToken);
            throw;
        }
    }

    public async Task<int> MarkArrivedAsync(CancellationToken cancellationToken = default)
    {
        await using var db = new MySqlConnection(_connectionString);
        await db.OpenAsync(cancellationToken);
        await using var command = new MySqlCommand(
            """
            UPDATE player_marches
            SET march_state='arrived'
            WHERE march_state='traveling' AND arrives_at<=UTC_TIMESTAMP()
            """, db);
        return await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static void ValidateId(string value, int maxLength, string name)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > maxLength ||
            value.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_'))
            throw new ArgumentException("Invalid identifier.", name);
    }
}
