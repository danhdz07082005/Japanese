using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace JapaneseMasteryBackendDotNet.Realtime;

public class WsConnectionManager
{
    private readonly ConcurrentDictionary<long, WebSocket> _userSockets = new();
    private readonly ConcurrentDictionary<WebSocket, long> _socketUsers = new();
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly MetricsTracker _metrics;

    public WsConnectionManager(MetricsTracker metrics)
    {
        _metrics = metrics;
    }

    public void Register(long userId, WebSocket socket)
    {
        _userSockets[userId] = socket;
        _socketUsers[socket] = userId;
        _metrics.SocketConnected();
    }

    public long? Unregister(WebSocket socket)
    {
        if (_socketUsers.TryRemove(socket, out var userId))
        {
            _userSockets.TryRemove(userId, out _);
            _metrics.SocketDisconnected();
            return userId;
        }
        return null;
    }

    public bool TryGetSocket(long userId, out WebSocket? socket)
    {
        return _userSockets.TryGetValue(userId, out socket);
    }

    public async Task SendAsync(WebSocket socket, object payload, CancellationToken cancellationToken = default)
    {
        if (socket.State != WebSocketState.Open) return;

        var json = JsonSerializer.Serialize(payload, JsonOptions);
        var bytes = Encoding.UTF8.GetBytes(json);
        _metrics.IncrementOut();

        await socket.SendAsync(
            new ArraySegment<byte>(bytes),
            WebSocketMessageType.Text,
            endOfMessage: true,
            cancellationToken: cancellationToken);
    }

    public async Task SendToUserAsync(long userId, object payload, CancellationToken cancellationToken = default)
    {
        if (_userSockets.TryGetValue(userId, out var socket))
        {
            await SendAsync(socket, payload, cancellationToken);
        }
    }

    public async Task BroadcastAsync(IEnumerable<long> userIds, object payload, CancellationToken cancellationToken = default)
    {
        foreach (var userId in userIds)
        {
            await SendToUserAsync(userId, payload, cancellationToken);
        }
    }
}
