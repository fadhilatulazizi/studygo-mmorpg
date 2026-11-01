using StudyGo.GameServer.WorldMap;
using StudyGo.GameServer.Marches;

var builder = WebApplication.CreateBuilder(args);

var gameDatabase = builder.Configuration.GetConnectionString("GameDatabase");
if (!string.IsNullOrWhiteSpace(gameDatabase))
{
    builder.Services.AddSingleton(new MySqlWorldSpawnRepository(gameDatabase));
    builder.Services.AddSingleton(new MySqlMarchRepository(gameDatabase));
    builder.Services.AddSingleton(new MySqlMarchSettlementRepository(gameDatabase));
    builder.Services.AddHostedService<StudyGo.GameServer.Workers.WorldSpawnWorker>();
    builder.Services.AddHostedService<StudyGo.GameServer.Workers.MarchArrivalWorker>();
    builder.Services.AddHostedService<StudyGo.GameServer.Workers.MarchSettlementWorker>();
}

var app = builder.Build();

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
    status = string.IsNullOrWhiteSpace(gameDatabase) ? "world-map-prototype-db-disabled" : "world-map-spawn-march-and-settlement-workers"
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

app.UseWebSockets();
app.Run();
