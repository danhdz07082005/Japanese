namespace JapaneseMasteryBackendDotNet.Services;

public class PvPMatchmakingBackgroundService : BackgroundService
{
    private readonly PvPService _pvpService;
    private readonly ILogger<PvPMatchmakingBackgroundService> _logger;

    public PvPMatchmakingBackgroundService(PvPService pvpService, ILogger<PvPMatchmakingBackgroundService> logger)
    {
        _pvpService = pvpService;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("PvP Matchmaking Background Service started.");

        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        while (!stoppingToken.IsCancellationRequested && await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await _pvpService.MatchPlayersAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during PvP matchmaking tick.");
            }
        }
    }
}

