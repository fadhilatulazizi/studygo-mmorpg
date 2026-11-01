using StudyGo.GameServer.Marches;

namespace StudyGo.GameServer.Workers;

public sealed class MarchSettlementWorker : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly ILogger<MarchSettlementWorker> _logger;

    public MarchSettlementWorker(IServiceProvider services, ILogger<MarchSettlementWorker> logger)
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
                var repository = scope.ServiceProvider.GetRequiredService<MySqlMarchSettlementRepository>();
                var result = await repository.RunCycleAsync(stoppingToken);
                if (result.Settled > 0 || result.Returned > 0)
                    _logger.LogInformation("March cycle settled {Settled} and returned {Returned} marches.",
                        result.Settled, result.Returned);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "March settlement cycle failed.");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
