using StudyGo.GameServer.Marches;

namespace StudyGo.GameServer.Workers;

public sealed class MarchArrivalWorker : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly ILogger<MarchArrivalWorker> _logger;

    public MarchArrivalWorker(IServiceProvider services, ILogger<MarchArrivalWorker> logger)
    {
        _services = services;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));
        do
        {
            try
            {
                using var scope = _services.CreateScope();
                var repository = scope.ServiceProvider.GetRequiredService<MySqlMarchRepository>();
                var arrived = await repository.MarkArrivedAsync(stoppingToken);
                if (arrived > 0)
                    _logger.LogInformation("March arrival worker marked {Count} marches as arrived.", arrived);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "March arrival cycle failed.");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
