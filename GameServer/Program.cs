var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new
{
    ok = true,
    service = "studygo-game-server",
    status = "scaffold"
}));

// Prototype only. Add authenticated sessions, authoritative simulation,
// instance management, rate limits and protocol validation before production.
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

        // Echo is only a connectivity test, not a game protocol.
        await socket.SendAsync(
            buffer.AsMemory(0, result.Count),
            result.MessageType,
            result.EndOfMessage,
            context.RequestAborted);
    }
});

app.UseWebSockets();
app.Run();
