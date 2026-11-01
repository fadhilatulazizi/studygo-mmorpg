using MySqlConnector;

namespace StudyGo.GameServer.WorldMap;

public sealed record SpawnCycleResult(
    long ZoneId,
    int Respawned,
    int Spawned,
    int ActiveCount,
    int FailedPlacementAttempts);

public sealed class MySqlWorldSpawnRepository
{
    private readonly string _connectionString;

    public MySqlWorldSpawnRepository(string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ArgumentException("A database connection string is required.", nameof(connectionString));

        _connectionString = connectionString;
    }

    public async Task<IReadOnlyList<SpawnCycleResult>> RunServerCycleAsync(
        string serverId,
        CancellationToken cancellationToken = default)
    {
        ValidateServerId(serverId);
        var zoneIds = new List<long>();

        await using (var connection = new MySqlConnection(_connectionString))
        {
            await connection.OpenAsync(cancellationToken);
            await using var command = new MySqlCommand(
                """
                SELECT id
                FROM world_spawn_zones
                WHERE server_id = @serverId AND is_enabled = 1
                ORDER BY id
                """, connection);
            command.Parameters.AddWithValue("@serverId", serverId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
                zoneIds.Add(reader.GetInt64("id"));
        }

        var results = new List<SpawnCycleResult>(zoneIds.Count);
        foreach (var zoneId in zoneIds)
        {
            cancellationToken.ThrowIfCancellationRequested();
            results.Add(await RunZoneCycleAsync(zoneId, cancellationToken));
        }

        return results;
    }

    public async Task<SpawnCycleResult> RunZoneCycleAsync(
        long zoneId,
        CancellationToken cancellationToken = default)
    {
        if (zoneId <= 0) throw new ArgumentOutOfRangeException(nameof(zoneId));

        await using var connection = new MySqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            string serverId;
            int regionSize;
            int mapMin;
            int mapMax;
            int minX;
            int minY;
            int maxX;
            int maxY;
            int maxAlive;
            int spawnBatch;
            long templateId;
            string objectType;
            string displayName;
            int objectLevel;
            long? maxCapacity;
            long? maxHp;
            int respawnSeconds;
            string? objectData;

            await using (var command = new MySqlCommand(
                """
                SELECT z.server_id, z.min_x, z.min_y, z.max_x, z.max_y,
                       z.max_alive, z.spawn_batch, z.template_id,
                       t.object_type, t.display_name, t.object_level,
                       t.max_capacity, t.max_hp, t.respawn_seconds,
                       CAST(t.object_data AS CHAR) AS object_data,
                       s.region_size, s.map_min_coordinate, s.map_max_coordinate,
                       s.server_status
                FROM world_spawn_zones z
                INNER JOIN world_spawn_templates t ON t.id = z.template_id
                INNER JOIN game_servers s ON s.server_id = z.server_id
                WHERE z.id = @zoneId AND z.is_enabled = 1 AND t.is_enabled = 1
                FOR UPDATE
                """, connection, transaction))
            {
                command.Parameters.AddWithValue("@zoneId", zoneId);
                await using var reader = await command.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    await transaction.RollbackAsync(cancellationToken);
                    return new(zoneId, 0, 0, 0, 0);
                }

                serverId = reader.GetString("server_id");
                minX = reader.GetInt32("min_x");
                minY = reader.GetInt32("min_y");
                maxX = reader.GetInt32("max_x");
                maxY = reader.GetInt32("max_y");
                maxAlive = reader.GetInt32("max_alive");
                spawnBatch = reader.GetInt32("spawn_batch");
                templateId = reader.GetInt64("template_id");
                objectType = reader.GetString("object_type");
                displayName = reader.GetString("display_name");
                objectLevel = reader.GetInt32("object_level");
                maxCapacity = reader.IsDBNull(reader.GetOrdinal("max_capacity"))
                    ? null : reader.GetInt64("max_capacity");
                maxHp = reader.IsDBNull(reader.GetOrdinal("max_hp"))
                    ? null : reader.GetInt64("max_hp");
                respawnSeconds = reader.GetInt32("respawn_seconds");
                objectData = reader.IsDBNull(reader.GetOrdinal("object_data"))
                    ? null : reader.GetString("object_data");
                regionSize = reader.GetInt32("region_size");
                mapMin = reader.GetInt32("map_min_coordinate");
                mapMax = reader.GetInt32("map_max_coordinate");

                var serverStatus = reader.GetString("server_status");
                if (serverStatus is not ("open" or "protected" or "transfer_locked"))
                {
                    await reader.CloseAsync();
                    await transaction.RollbackAsync(cancellationToken);
                    return new(zoneId, 0, 0, 0, 0);
                }
            }

            if (minX > maxX || minY > maxY || minX < mapMin || minY < mapMin ||
                maxX > mapMax || maxY > mapMax || regionSize <= 0)
                throw new InvalidOperationException($"Spawn zone {zoneId} is outside the configured server map.");

            var respawned = await RespawnDueAsync(
                connection, transaction, zoneId, cancellationToken);

            var activeCount = await CountAliveAsync(
                connection, transaction, zoneId, cancellationToken);

            var targetCount = Math.Min(maxAlive, activeCount + spawnBatch);
            var spawned = 0;
            var failedAttempts = 0;

            while (activeCount + spawned < targetCount && failedAttempts < spawnBatch * 30)
            {
                var x = Random.Shared.Next(minX, checked(maxX + 1));
                var y = Random.Shared.Next(minY, checked(maxY + 1));
                var objectId = $"spawn-{Guid.NewGuid():N}";
                var regionX = (int)Math.Floor((double)x / regionSize);
                var regionY = (int)Math.Floor((double)y / regionSize);
                var capacity = objectType == "resource" ? maxCapacity : maxHp;

                try
                {
                    await using (var insertObject = new MySqlCommand(
                        """
                        INSERT INTO world_map_objects
                            (object_id, server_id, region_x, region_y, coordinate_x, coordinate_y,
                             object_type, object_level, display_name, object_status,
                             remaining_capacity, object_data)
                        VALUES
                            (@objectId, @serverId, @regionX, @regionY, @x, @y,
                             @objectType, @objectLevel, @displayName, 'active',
                             @capacity, @objectData)
                        """, connection, transaction))
                    {
                        insertObject.Parameters.AddWithValue("@objectId", objectId);
                        insertObject.Parameters.AddWithValue("@serverId", serverId);
                        insertObject.Parameters.AddWithValue("@regionX", regionX);
                        insertObject.Parameters.AddWithValue("@regionY", regionY);
                        insertObject.Parameters.AddWithValue("@x", x);
                        insertObject.Parameters.AddWithValue("@y", y);
                        insertObject.Parameters.AddWithValue("@objectType", objectType);
                        insertObject.Parameters.AddWithValue("@objectLevel", objectLevel);
                        insertObject.Parameters.AddWithValue("@displayName", displayName);
                        insertObject.Parameters.AddWithValue("@capacity", capacity.HasValue ? capacity.Value : DBNull.Value);
                        insertObject.Parameters.AddWithValue("@objectData", objectData is null ? DBNull.Value : objectData);
                        await insertObject.ExecuteNonQueryAsync(cancellationToken);
                    }

                    await using (var insertInstance = new MySqlCommand(
                        """
                        INSERT INTO world_spawn_instances
                            (object_id, zone_id, template_id, instance_state)
                        VALUES (@objectId, @zoneId, @templateId, 'alive')
                        """, connection, transaction))
                    {
                        insertInstance.Parameters.AddWithValue("@objectId", objectId);
                        insertInstance.Parameters.AddWithValue("@zoneId", zoneId);
                        insertInstance.Parameters.AddWithValue("@templateId", templateId);
                        await insertInstance.ExecuteNonQueryAsync(cancellationToken);
                    }

                    spawned++;
                }
                catch (MySqlException ex) when (ex.Number == 1062)
                {
                    failedAttempts++;
                }
            }

            activeCount += spawned;
            await transaction.CommitAsync(cancellationToken);
            return new(zoneId, respawned, spawned, activeCount, failedAttempts);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    private static async Task<int> RespawnDueAsync(
        MySqlConnection connection,
        MySqlTransaction transaction,
        long zoneId,
        CancellationToken cancellationToken)
    {
        await using var command = new MySqlCommand(
            """
            UPDATE world_spawn_instances i
            INNER JOIN world_map_objects o ON o.object_id = i.object_id
            INNER JOIN world_spawn_templates t ON t.id = i.template_id
            SET i.instance_state = 'alive',
                i.respawn_at = NULL,
                o.object_status = 'active',
                o.remaining_capacity = CASE
                    WHEN t.object_type = 'resource' THEN t.max_capacity
                    WHEN t.object_type = 'monster' THEN t.max_hp
                    ELSE o.remaining_capacity
                END
            WHERE i.zone_id = @zoneId
              AND i.instance_state IN ('depleted','defeated','respawning')
              AND i.respawn_at IS NOT NULL
              AND i.respawn_at <= UTC_TIMESTAMP()
            """, connection, transaction);
        command.Parameters.AddWithValue("@zoneId", zoneId);
        return await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<int> CountAliveAsync(
        MySqlConnection connection,
        MySqlTransaction transaction,
        long zoneId,
        CancellationToken cancellationToken)
    {
        await using var command = new MySqlCommand(
            """
            SELECT COUNT(*)
            FROM world_spawn_instances
            WHERE zone_id = @zoneId AND instance_state = 'alive'
            """, connection, transaction);
        command.Parameters.AddWithValue("@zoneId", zoneId);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task<IReadOnlyList<SpawnCycleResult>> RunAllEnabledServersAsync(
        CancellationToken cancellationToken = default)
    {
        var serverIds = new List<string>();
        await using (var connection = new MySqlConnection(_connectionString))
        {
            await connection.OpenAsync(cancellationToken);
            await using var command = new MySqlCommand(
                """
                SELECT DISTINCT z.server_id
                FROM world_spawn_zones z
                INNER JOIN game_servers s ON s.server_id = z.server_id
                WHERE z.is_enabled = 1
                  AND s.server_status IN ('open','protected','transfer_locked')
                ORDER BY z.server_id
                """, connection);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
                serverIds.Add(reader.GetString("server_id"));
        }

        var results = new List<SpawnCycleResult>();
        foreach (var serverId in serverIds)
        {
            cancellationToken.ThrowIfCancellationRequested();
            results.AddRange(await RunServerCycleAsync(serverId, cancellationToken));
        }

        return results;
    }

    private static void ValidateServerId(string serverId)
    {
        if (string.IsNullOrWhiteSpace(serverId) || serverId.Length > 48 ||
            serverId.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_'))
            throw new ArgumentException("Invalid server id.", nameof(serverId));
    }
}
