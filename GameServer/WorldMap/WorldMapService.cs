namespace StudyGo.GameServer.WorldMap;

public sealed record WorldMapObject(
    string Id,
    string ServerId,
    int X,
    int Y,
    string Type,
    int Level,
    string Name,
    string? OwnerId,
    long? RemainingCapacity,
    string Status);

public sealed record WorldMapRegion(
    string ServerId,
    int RegionX,
    int RegionY,
    int MinX,
    int MinY,
    int MaxX,
    int MaxY,
    IReadOnlyList<WorldMapObject> Objects);

public sealed class WorldMapOptions
{
    public int RegionSize { get; init; } = 64;
    public int MapMinCoordinate { get; init; } = 0;
    public int MapMaxCoordinate { get; init; } = 4095;
}

public sealed class WorldMapService
{
    private readonly WorldMapOptions _options;
    private readonly IReadOnlyList<WorldMapObject> _objects;

    public WorldMapService(WorldMapOptions options)
    {
        if (options.RegionSize <= 0 || options.MapMinCoordinate >= options.MapMaxCoordinate)
            throw new ArgumentException("Invalid world map configuration.", nameof(options));

        _options = options;
        _objects = BuildDevelopmentSeed();
    }

    public WorldMapRegion GetRegion(string serverId, int regionX, int regionY)
    {
        ValidateServerId(serverId);
        var minX = checked(regionX * _options.RegionSize);
        var minY = checked(regionY * _options.RegionSize);
        var maxX = minX + _options.RegionSize - 1;
        var maxY = minY + _options.RegionSize - 1;
        ValidateBounds(minX, minY);
        ValidateBounds(maxX, maxY);

        var objects = _objects
            .Where(x => x.ServerId == serverId &&
                        x.X >= minX && x.X <= maxX &&
                        x.Y >= minY && x.Y <= maxY)
            .ToArray();

        return new WorldMapRegion(serverId, regionX, regionY, minX, minY, maxX, maxY, objects);
    }

    public IReadOnlyList<WorldMapObject> GetNearby(
        string serverId, int centerX, int centerY, int radius, int limit = 200)
    {
        ValidateServerId(serverId);
        ValidateBounds(centerX, centerY);
        if (radius is < 1 or > 256) throw new ArgumentOutOfRangeException(nameof(radius));
        if (limit is < 1 or > 500) throw new ArgumentOutOfRangeException(nameof(limit));

        return _objects
            .Where(x => x.ServerId == serverId &&
                        Math.Abs(x.X - centerX) <= radius &&
                        Math.Abs(x.Y - centerY) <= radius)
            .OrderBy(x => DistanceSquared(x.X, x.Y, centerX, centerY))
            .Take(limit)
            .ToArray();
    }

    public IReadOnlyList<WorldMapObject> Search(
        string serverId, string? type, string? query, int? minLevel, int? maxLevel, int limit = 100)
    {
        ValidateServerId(serverId);
        if (limit is < 1 or > 200) throw new ArgumentOutOfRangeException(nameof(limit));
        if (minLevel < 0 || maxLevel < 0 || (minLevel.HasValue && maxLevel.HasValue && minLevel > maxLevel))
            throw new ArgumentException("Invalid level range.");

        var normalizedType = string.IsNullOrWhiteSpace(type) ? null : type.Trim().ToLowerInvariant();
        var normalizedQuery = string.IsNullOrWhiteSpace(query) ? null : query.Trim();

        return _objects
            .Where(x => x.ServerId == serverId)
            .Where(x => normalizedType == null || x.Type.Equals(normalizedType, StringComparison.OrdinalIgnoreCase))
            .Where(x => normalizedQuery == null ||
                        x.Name.Contains(normalizedQuery, StringComparison.OrdinalIgnoreCase) ||
                        x.Id.Contains(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            .Where(x => !minLevel.HasValue || x.Level >= minLevel.Value)
            .Where(x => !maxLevel.HasValue || x.Level <= maxLevel.Value)
            .OrderBy(x => x.Level)
            .Take(limit)
            .ToArray();
    }

    private void ValidateBounds(int x, int y)
    {
        if (x < _options.MapMinCoordinate || y < _options.MapMinCoordinate ||
            x > _options.MapMaxCoordinate || y > _options.MapMaxCoordinate)
            throw new ArgumentOutOfRangeException(nameof(x), "Coordinates are outside this server's world map.");
    }

    private static void ValidateServerId(string serverId)
    {
        if (string.IsNullOrWhiteSpace(serverId) || serverId.Length > 48 ||
            serverId.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_'))
            throw new ArgumentException("Invalid server id.", nameof(serverId));
    }

    private static long DistanceSquared(int x1, int y1, int x2, int y2)
    {
        var dx = (long)x1 - x2;
        var dy = (long)y1 - y2;
        return dx * dx + dy * dy;
    }

    private static IReadOnlyList<WorldMapObject> BuildDevelopmentSeed() =>
    [
        new("castle-demo-001", "aetheria-01", 12, 14, "castle", 3, "Demo Castle", "player-demo", null, "active"),
        new("node-food-001", "aetheria-01", 18, 20, "food", 1, "Food Field", null, 12000, "available"),
        new("node-wood-001", "aetheria-01", 25, 16, "wood", 2, "Whispering Forest", null, 18000, "available"),
        new("node-stone-001", "aetheria-01", 31, 28, "stone", 2, "Stone Deposit", null, 16000, "available"),
        new("node-iron-001", "aetheria-01", 42, 35, "iron", 3, "Iron Vein", null, 22000, "available"),
        new("monster-001", "aetheria-01", 38, 18, "monster", 2, "Ashfang Beast", null, null, "alive"),
        new("ruin-001", "aetheria-01", 55, 44, "ruin", 4, "Forgotten Shrine", null, null, "available"),
        new("castle-demo-002", "aetheria-02", 12, 14, "castle", 5, "Other Server Castle", "player-other", null, "active")
    ];
}
