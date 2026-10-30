using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using JapaneseMasteryBackendDotNet.Logging;
using JapaneseMasteryBackendDotNet.Services;

namespace JapaneseMasteryBackendDotNet.Realtime;

public class WsPvPMiddleware
{
    private readonly RequestDelegate _next;
    private readonly WsConnectionManager _connectionManager;
    private readonly PvPMatchEngine _matchEngine;
    private readonly PvPService _pvpService;
    private readonly MetricsTracker _metrics;
    private readonly PyTunnelLogSink _logSink;
    private readonly ILogger<WsPvPMiddleware> _logger;

    public WsPvPMiddleware(
        RequestDelegate next,
        WsConnectionManager connectionManager,
        PvPMatchEngine matchEngine,
        PvPService pvpService,
        MetricsTracker metrics,
        PyTunnelLogSink logSink,
        ILogger<WsPvPMiddleware> logger)
    {
        _next = next;
        _connectionManager = connectionManager;
        _matchEngine = matchEngine;
        _pvpService = pvpService;
        _metrics = metrics;
        _logSink = logSink;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (context.Request.Path == "/ws/pvp")
        {
            if (context.WebSockets.IsWebSocketRequest)
            {
                using var webSocket = await context.WebSockets.AcceptWebSocketAsync();
                await HandleWebSocketSessionAsync(context, webSocket);
            }
            else
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                await context.Response.WriteAsync("Expected WebSocket upgrade request.");
            }
        }
        else
        {
            await _next(context);
        }
    }

    private async Task HandleWebSocketSessionAsync(HttpContext context, WebSocket webSocket)
    {
        var buffer = new byte[1024 * 4];
        long currentUserId = 0;
        string currentUsername = "Guest";

        var clientIp = context.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1";
        _logSink.Enqueue("PVP-SOCKET", "CONNECT", $"New WebSocket client connected from {clientIp}");

        try
        {
            while (webSocket.State == WebSocketState.Open)
            {
                var result = await webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    break;
                }

                _metrics.IncrementIn();
                var messageStr = Encoding.UTF8.GetString(buffer, 0, result.Count);

                using var doc = JsonDocument.Parse(messageStr);
                var root = doc.RootElement;

                if (!root.TryGetProperty("action", out var actionProp)) continue;
                var action = actionProp.GetString();

                switch (action)
                {
                    case "auth":
                    case "register":
                        if (root.TryGetProperty("userId", out var uId))
                        {
                            currentUserId = uId.GetInt64();
                            currentUsername = root.TryGetProperty("username", out var uName) ? uName.GetString() ?? "Player" : $"Player {currentUserId}";
                            _connectionManager.Register(currentUserId, webSocket);
                            _logSink.Enqueue("PVP-SOCKET", "AUTH", $"Authenticated socket for '{currentUsername}' (UID: {currentUserId})");
                            await _connectionManager.SendAsync(webSocket, new { @event = "authenticated", userId = currentUserId });
                        }
                        break;

                    case "ping":
                        var t = root.TryGetProperty("t", out var tProp) ? tProp.GetInt64() : 0;
                        var fps = root.TryGetProperty("fps", out var fpsProp) ? fpsProp.GetInt32() : 0;
                        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                        long rtt = 0;
                        if (t > 0)
                        {
                            rtt = now - t;
                            if (rtt >= 0 && rtt < 2000) _metrics.RecordRtt(rtt);
                        }

                        if (currentUserId > 0)
                        {
                            _connectionManager.RecordTelemetry(currentUserId, currentUsername, fps, rtt);
                            if (_connectionManager.ShouldLogTelemetry(currentUserId, fps))
                            {
                                var badge = fps >= 55 ? "🟢 60fps" : (fps >= 30 ? "🟡 30fps" : "🔴 Lag Alert");
                                _logSink.Enqueue("PVP-SOCKET", "FPS", $"[Telemetry] Player '{currentUsername}' | FPS: {fps} ({badge}) | Ping: {rtt}ms");
                            }
                        }

                        await _connectionManager.SendAsync(webSocket, new { @event = "pong", t = t, serverTime = now });
                        break;

                    case "join_queue":
                        if (currentUserId > 0)
                        {
                            _logSink.Enqueue("PVP-SOCKET", "ACTION", $"[Action: join_queue] User '{currentUsername}' (UID: {currentUserId}) entered matchmaking queue");
                            await _matchEngine.HandleJoinQueueAsync(currentUserId, currentUsername);
                        }
                        break;

                    case "leave_queue":
                        if (currentUserId > 0)
                        {
                            _logSink.Enqueue("PVP-SOCKET", "ACTION", $"[Action: leave_queue] User '{currentUsername}' (UID: {currentUserId}) cancelled matchmaking");
                            _matchEngine.LeaveQueue(currentUserId);
                            await _connectionManager.SendAsync(webSocket, new { @event = "queue_left" });
                        }
                        break;

                    case "create_lobby":
                        if (currentUserId > 0)
                        {
                            _logSink.Enqueue("PVP-SOCKET", "ACTION", $"[Action: create_lobby] User '{currentUsername}' (UID: {currentUserId}) requested new private room");
                            await _matchEngine.CreateLobbyAsync(currentUserId, currentUsername);
                        }
                        break;

                    case "join_lobby":
                        if (currentUserId > 0 && root.TryGetProperty("code", out var codeProp))
                        {
                            var code = codeProp.GetString() ?? "";
                            _logSink.Enqueue("PVP-SOCKET", "ACTION", $"[Action: join_lobby] User '{currentUsername}' joining room {code}");
                            await _matchEngine.JoinLobbyAsync(code, currentUserId, currentUsername);
                        }
                        break;

                    case "progress":
                        if (currentUserId > 0 && root.TryGetProperty("progress", out var progProp))
                        {
                            var prog = progProp.GetInt32();
                            _pvpService.UpdateProgress(currentUserId, prog);
                            await _matchEngine.HandleProgressSyncAsync(currentUserId, prog);
                        }
                        break;

                    case "finish":
                        if (currentUserId > 0 && root.TryGetProperty("timeMs", out var tmProp))
                        {
                            var timeMs = tmProp.GetInt64();
                            _logSink.Enqueue("PVP-SOCKET", "ACTION", $"[Action: finish] User '{currentUsername}' (UID: {currentUserId}) submitted finish time: {timeMs}ms");
                            await _pvpService.FinishMatchAsync(currentUserId, timeMs);
                            await _matchEngine.HandleFinishMatchAsync(currentUserId, timeMs);
                        }
                        break;
                }
            }
        }
        catch (WebSocketException)
        {
            // Expected when client closes tab/window abruptly
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "WebSocket handler notice on UID {UserId}", currentUserId);
        }
        finally
        {
            _connectionManager.Unregister(webSocket);
            if (currentUserId > 0)
            {
                await _matchEngine.HandleDisconnectAsync(currentUserId);
                _logSink.Enqueue("PVP-SOCKET", "DISCONNECT", $"Client '{currentUsername}' (UID: {currentUserId}) disconnected");
            }

            if (webSocket.State == WebSocketState.Open || webSocket.State == WebSocketState.CloseReceived)
            {
                try
                {
                    await webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None);
                }
                catch { }
            }
        }
    }
}
