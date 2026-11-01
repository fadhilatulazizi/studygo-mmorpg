using StudyGo.GameServer.WorldMap;
using StudyGo.GameServer.Marches;
using StudyGo.GameServer.Auth;
using System.Security.Claims;

var builder = WebApplication.CreateBuilder(args);

var gameDatabase = builder.Configuration.GetConnectionString("GameDatabase");
var jwtConfigured = builder.Services.AddGameJwtAuthentication(builder.Configuration);
var gameApiEnabled = jwtConfigured && !string.IsNullOrWhiteSpace(gameDatabase);
if (!string.IsNullOrWhiteSpace(gameDatabase))
{
    builder.Services.AddSingleton(new MySqlWorldSpawnRepository(gameDatabase));
    builder.Services.AddSingleton(new MySqlMarchRepository(gameDatabase));
    builder.Services.AddSingleton(new MySqlMarchSettlementRepository(gameDatabase));
    builder.Services.AddSingleton(new MySqlMarchApiRepository(gameDatabase));
    builder.Services.AddHostedService<StudyGo.GameServer.Workers.WorldSpawnWorker>();
    builder.Services.AddHostedService<StudyGo.GameServer.Workers.MarchArrivalWorker>();
    builder.Services.AddHostedService<StudyGo.GameServer.Workers.MarchSettlementWorker>();
}

var app = builder.Build();
app.UseWebSockets();
app.UseAuthentication();
app.UseAuthorization();

var worldMap = new WorldMapService(new WorldMapOptions
{
    RegionSize = 64,
    MapMinCoordinate = 0,
    MapMaxCoordinate = 4095
});

app.MapGet("/health", () => Results.Ok(new
{
    ok = true,
    service = "studygo-game-server",
    status = string.IsNullOrWhiteSpace(gameDatabase) ? "world-map-prototype-db-disabled" : "world-map-spawn-march-and-settlement-workers",
    marchApiEnabled = gameApiEnabled
}));

app.MapGet("/world/region", (string serverId, int regionX, int regionY) =>
{
    try
    {
        return Results.Ok(worldMap.GetRegion(serverId, regionX, regionY));
    }
    catch (ArgumentException ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

app.MapGet("/world/map", (string serverId, int centerX, int centerY, int radius, int? limit) =>
{
    try
    {
        var objects = worldMap.GetNearby(serverId, centerX, centerY, radius, limit ?? 200);
        return Results.Ok(new
        {
            serverId,
            centerX,
            centerY,
            radius,
            count = objects.Count,
            objects
        });
    }
    catch (ArgumentException ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});

app.MapGet("/world/search", (
    string serverId,
    string? type,
    string? query,
    int? minLevel,
    int? maxLevel,
    int? limit) =>
{
    try
    {
        var results = worldMap.Search(serverId, type, query, minLevel, maxLevel, limit ?? 100);
        return Results.Ok(new { serverId, count = results.Count, results });
    }
    catch (ArgumentException ex)
    {
        return Results.BadRequest(new { error = ex.Message });
    }
});


if (gameApiEnabled)
{
var marchApi = app.MapGroup("/api/game").RequireAuthorization();

marchApi.MapPost("/marches", async (
    SendMarchRequest request, ClaimsPrincipal user,
    MySqlMarchApiRepository identity, MySqlMarchRepository marches,
    CancellationToken ct) =>
{
    if (!long.TryParse(user.FindFirstValue("sub"), out var userId) || userId <= 0)
        return Results.Unauthorized();
    var serverId = user.FindFirstValue("server_id");
    if (string.IsNullOrWhiteSpace(serverId)) return Results.Unauthorized();
    var playerId = await identity.ResolvePlayerIdAsync(userId, ct);
    if (playerId is null) return Results.NotFound(new { error = "game_player_not_found" });
    var troops = request.Troops?.Select(t => new MarchTroopRequest(t.TroopCode ?? "", t.Quantity)).ToArray()
        ?? Array.Empty<MarchTroopRequest>();
    var result = await marches.SendAsync(serverId, playerId.Value, request.RequestId ?? "",
        request.DestinationObjectId ?? "", request.MissionType ?? "", troops, ct);
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

marchApi.MapGet("/marches", async (
    bool? includeReturned, ClaimsPrincipal user, MySqlMarchApiRepository identity,
    CancellationToken ct) =>
{
    if (!long.TryParse(user.FindFirstValue("sub"), out var userId) || userId <= 0)
        return Results.Unauthorized();
    var serverId = user.FindFirstValue("server_id");
    if (string.IsNullOrWhiteSpace(serverId)) return Results.Unauthorized();
    var playerId = await identity.ResolvePlayerIdAsync(userId, ct);
    if (playerId is null) return Results.NotFound(new { error = "game_player_not_found" });
    var items = await identity.GetPlayerMarchesAsync(serverId, playerId.Value, includeReturned ?? false, ct);
    return Results.Ok(new { serverId, count = items.Count, marches = items });
});

marchApi.MapPost("/marches/{marchId}/recall", async (
    string marchId, ClaimsPrincipal user, MySqlMarchApiRepository identity,
    MySqlMarchSettlementRepository settlement, CancellationToken ct) =>
{
    if (!long.TryParse(user.FindFirstValue("sub"), out var userId) || userId <= 0)
        return Results.Unauthorized();
    var serverId = user.FindFirstValue("server_id");
    if (string.IsNullOrWhiteSpace(serverId)) return Results.Unauthorized();
    var playerId = await identity.ResolvePlayerIdAsync(userId, ct);
    if (playerId is null) return Results.NotFound(new { error = "game_player_not_found" });
    var result = await settlement.RecallAsync(serverId, playerId.Value, marchId, ct);
    return result.Success ? Results.Ok(result) : Results.BadRequest(result);
});

marchApi.MapGet("/marches/{marchId}/scout-report", async (
    string marchId, ClaimsPrincipal user, MySqlMarchApiRepository identity,
    CancellationToken ct) =>
{
    if (!long.TryParse(user.FindFirstValue("sub"), out var userId) || userId <= 0)
        return Results.Unauthorized();
    var serverId = user.FindFirstValue("server_id");
    if (string.IsNullOrWhiteSpace(serverId)) return Results.Unauthorized();
    var playerId = await identity.ResolvePlayerIdAsync(userId, ct);
    if (playerId is null) return Results.NotFound(new { error = "game_player_not_found" });
    var report = await identity.GetScoutReportAsync(serverId, playerId.Value, marchId, ct);
    return report is null ? Results.NotFound(new { error = "scout_report_not_found_or_expired" })
        : Results.Content(report, "application/json");
});

}

app.Map("/ws", async context =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    var buffer = new byte[4096];

    while (socket.State == System.Net.WebSockets.WebSocketState.Open)
    {
        var result = await socket.ReceiveAsync(buffer, context.RequestAborted);
        if (result.MessageType == System.Net.WebSockets.WebSocketMessageType.Close)
        {
            await socket.CloseAsync(
                System.Net.WebSockets.WebSocketCloseStatus.NormalClosure,
                "Client closed",
                context.RequestAborted);
            break;
        }

        // Temporary connectivity echo. Replace with authenticated game messages.
        await socket.SendAsync(
            buffer.AsMemory(0, result.Count),
            result.MessageType,
            result.EndOfMessage,
            context.RequestAborted);
    }
});

app.Run();

public sealed record SendMarchRequest(string? RequestId, string? DestinationObjectId, string? MissionType, List<SendMarchTroop>? Troops);
public sealed record SendMarchTroop(string? TroopCode, long Quantity);
