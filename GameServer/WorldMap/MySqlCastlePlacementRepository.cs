using MySqlConnector;

namespace StudyGo.GameServer.WorldMap;

public enum CastlePlacementStatus
{
    Created,
    PlayerNotFound,
    ServerUnavailable,
    OutOfBounds,
    AlreadyHasCastle,
    TileOccupied
}

public sealed record CastlePlacementResult(
    CastlePlacementStatus Status,
    string? CastleId = null,
    string? ServerId = null,
    int? X = null,
    int? Y = null);

public sealed class MySqlCastlePlacementRepository
{
    private readonly string _connectionString;

    public MySqlCastlePlacementRepository(string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new ArgumentException("A database connection string is required.", nameof(connectionString));

        _connectionString = connectionString;
    }

    public async Task<CastlePlacementResult> PlaceAsync(
        string serverId,
        long playerId,
        int x,
        int y,
        string castleName,
        CancellationToken cancellationToken = default)
    {
        ValidateServerId(serverId);
        if (playerId <= 0) throw new ArgumentOutOfRangeException(nameof(playerId));
        if (string.IsNullOrWhiteSpace(castleName) || castleName.Trim().Length > 80)
            throw new ArgumentException("Castle name must contain 1–80 characters.", nameof(castleName));

        await using var connection = new MySqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            int regionSize;
            int minCoordinate;
            int maxCoordinate;

            await using (var serverCommand = new MySqlCommand(
                """
                SELECT region_size, map_min_coordinate, map_max_coordinate, server_status
                FROM game_servers
                WHERE server_id = @serverId
                FOR UPDATE
                """, connection, transaction))
            {
                serverCommand.Parameters.AddWithValue("@serverId", serverId);
                await using var reader = await serverCommand.ExecuteReaderAsync(cancellationToken);
                if (!await reader.ReadAsync(cancellationToken))
                {
                    await transaction.RollbackAsync(cancellationToken);
                    return new(CastlePlacementStatus.ServerUnavailable);
                }

                regionSize = reader.GetInt32("region_size");
                minCoordinate = reader.GetInt32("map_min_coordinate");
                maxCoordinate = reader.GetInt32("map_max_coordinate");
                var status = reader.GetString("server_status");
                if (status is not ("open" or "protected" or "transfer_locked"))
                {
                    await reader.CloseAsync();
                    await transaction.RollbackAsync(cancellationToken);
                    return new(CastlePlacementStatus.ServerUnavailable);
                }
            }

            if (x < minCoordinate || y < minCoordinate || x > maxCoordinate || y > maxCoordinate)
            {
                await transaction.RollbackAsync(cancellationToken);
                return new(CastlePlacementStatus.OutOfBounds);
            }

            await using (var playerCommand = new MySqlCommand(
                "SELECT id FROM game_players WHERE id = @playerId FOR UPDATE",
                connection, transaction))
            {
                playerCommand.Parameters.AddWithValue("@playerId", playerId);
                var player = await playerCommand.ExecuteScalarAsync(cancellationToken);
                if (player is null)
                {
                    await transaction.RollbackAsync(cancellationToken);
                    return new(CastlePlacementStatus.PlayerNotFound);
                }
            }

            await using (var existingCommand = new MySqlCommand(
                """
                SELECT id FROM player_castles
                WHERE server_id = @serverId AND player_id = @playerId
                LIMIT 1
                FOR UPDATE
                """, connection, transaction))
            {
                existingCommand.Parameters.AddWithValue("@serverId", serverId);
                existingCommand.Parameters.AddWithValue("@playerId", playerId);
                var existing = await existingCommand.ExecuteScalarAsync(cancellationToken);
                if (existing is not null)
                {
                    await transaction.RollbackAsync(cancellationToken);
                    return new(CastlePlacementStatus.AlreadyHasCastle);
                }
            }

            var castleId = $"castle-{Guid.NewGuid():N}";
            var regionX = (int)Math.Floor((double)x / regionSize);
            var regionY = (int)Math.Floor((double)y / regionSize);

            await using (var objectCommand = new MySqlCommand(
                """
                INSERT INTO world_map_objects
                    (object_id, server_id, region_x, region_y, coordinate_x, coordinate_y,
                     object_type, object_level, display_name, owner_player_id, object_status)
                VALUES
                    (@objectId, @serverId, @regionX, @regionY, @x, @y,
                     'castle', 1, @castleName, @playerId, 'active')
                """, connection, transaction))
            {
                objectCommand.Parameters.AddWithValue("@objectId", castleId);
                objectCommand.Parameters.AddWithValue("@serverId", serverId);
                objectCommand.Parameters.AddWithValue("@regionX", regionX);
                objectCommand.Parameters.AddWithValue("@regionY", regionY);
                objectCommand.Parameters.AddWithValue("@x", x);
                objectCommand.Parameters.AddWithValue("@y", y);
                objectCommand.Parameters.AddWithValue("@castleName", castleName.Trim());
                objectCommand.Parameters.AddWithValue("@playerId", playerId);
                await objectCommand.ExecuteNonQueryAsync(cancellationToken);
            }

            await using (var castleCommand = new MySqlCommand(
                """
                INSERT INTO player_castles
                    (server_id, player_id, map_object_id, castle_name, castle_level)
                VALUES
                    (@serverId, @playerId, @objectId, @castleName, 1)
                """, connection, transaction))
            {
                castleCommand.Parameters.AddWithValue("@serverId", serverId);
                castleCommand.Parameters.AddWithValue("@playerId", playerId);
                castleCommand.Parameters.AddWithValue("@objectId", castleId);
                castleCommand.Parameters.AddWithValue("@castleName", castleName.Trim());
                await castleCommand.ExecuteNonQueryAsync(cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);
            return new(CastlePlacementStatus.Created, castleId, serverId, x, y);
        }
        catch (MySqlException ex) when (ex.Number == 1062)
        {
            await transaction.RollbackAsync(cancellationToken);
            return new(CastlePlacementStatus.TileOccupied);
        }
        catch
        {
            await transaction.RollbackAsync(cancellationToken);
            throw;
        }
    }

    private static void ValidateServerId(string serverId)
    {
        if (string.IsNullOrWhiteSpace(serverId) || serverId.Length > 48 ||
            serverId.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_'))
            throw new ArgumentException("Invalid server id.", nameof(serverId));
    }
}
