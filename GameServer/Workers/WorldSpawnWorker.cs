using StudyGo.GameServer.WorldMap;

namespace StudyGo.GameServer.Workers;

public sealed class WorldSpawnWorker : BackgroundService
{
    private readonly MySqlWorldSpawnRepository _repository;
    private readonly ILogger<WorldSpawnWorker> _logger;

    public WorldSpawnWorker(
        MySqlWorldSpawnRepository repository,
        ILogger<WorldSpawnWorker> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var results = await _repository.RunAllEnabledServersAsync(stoppingToken);
                foreach (var result in results)
                {
                    if (result.Spawned > 0 || result.Respawned > 0)
                    {
                        _logger.LogInformation(
                            "Spawn zone {ZoneId}: spawned={Spawned}, respawned={Respawned}, active={Active}",
                            result.ZoneId, result.Spawned, result.Respawned, result.ActiveCount);
                    }
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "World spawn cycle failed.");
            }

            try
            {
                await timer.WaitForNextTickAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
        }
    }
}
