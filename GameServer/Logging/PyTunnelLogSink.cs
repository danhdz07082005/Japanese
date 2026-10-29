using System.Text.Json;
using System.Threading.Channels;

namespace JapaneseMasteryBackendDotNet.Logging;

public record PyTunnelLogEntry(string Time, string Source, string Level, string Message);

public class PyTunnelLogSink : BackgroundService
{
    private readonly Channel<PyTunnelLogEntry> _channel = Channel.CreateBounded<PyTunnelLogEntry>(new BoundedChannelOptions(500)
    {
        FullMode = BoundedChannelFullMode.DropOldest
    });

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _config;
    private readonly ILogger<PyTunnelLogSink> _logger;

    public PyTunnelLogSink(
        IHttpClientFactory httpClientFactory,
        IConfiguration config,
        ILogger<PyTunnelLogSink> logger)
    {
        _httpClientFactory = httpClientFactory;
        _config = config;
        _logger = logger;
    }

    public void Enqueue(string source, string level, string message)
    {
        var entry = new PyTunnelLogEntry(
            Time: DateTime.Now.ToString("HH:mm:ss"),
            Source: source,
            Level: level,
            Message: message
        );
        _channel.Writer.TryWrite(entry);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var endpoint = _config["App:PyTunnel:LogEndpoint"] ?? "http://127.0.0.1:8787/api/terminal-logs";
        using var client = _httpClientFactory.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(2);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var entry = await _channel.Reader.ReadAsync(stoppingToken);
                var content = new StringContent(
                    JsonSerializer.Serialize(new
                    {
                        time = entry.Time,
                        source = entry.Source,
                        level = entry.Level,
                        message = entry.Message
                    }),
                    System.Text.Encoding.UTF8,
                    "application/json");

                _ = client.PostAsync(endpoint, content, stoppingToken).ContinueWith(_ => { }, TaskContinuationOptions.OnlyOnFaulted);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch
            {
                // Non-blocking fire and forget: PyTunnel may be offline or starting up
            }
        }
    }
}
