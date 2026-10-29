using System.Collections.Concurrent;
using System.Text;
using System.Text.RegularExpressions;
using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.Logging;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Realtime;

public class PvPMatchState
{
    public string MatchId { get; init; } = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();
    public long Player1Id { get; init; }
    public string Player1Name { get; set; } = "Player 1";
    public long Player2Id { get; init; }
    public string Player2Name { get; set; } = "Player 2";
    public string Paragraph { get; init; } = "";
    public string Romaji { get; init; } = "";
    public int Player1Progress { get; set; } = 0;
    public int Player2Progress { get; set; } = 0;
    public long? WinnerId { get; set; }
    public bool IsFinished { get; set; }
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
}

public class PvPMatchEngine
{
    private readonly WsConnectionManager _connectionManager;
    private readonly MetricsTracker _metrics;
    private readonly PyTunnelLogSink _logSink;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly RomajiConverter _romajiConverter;
    private readonly ILogger<PvPMatchEngine> _logger;

    private readonly List<string> _paragraphs = new();
    private readonly Random _random = new();

    private readonly ConcurrentQueue<long> _matchmakingQueue = new();
    private readonly ConcurrentDictionary<string, PvPMatchState> _activeMatches = new();
    private readonly ConcurrentDictionary<long, string> _userMatchMap = new();
    private readonly ConcurrentDictionary<string, (long HostId, string HostName)> _lobbies = new();

    public PvPMatchEngine(
        WsConnectionManager connectionManager,
        MetricsTracker metrics,
        PyTunnelLogSink logSink,
        IServiceScopeFactory scopeFactory,
        RomajiConverter romajiConverter,
        ILogger<PvPMatchEngine> logger)
    {
        _connectionManager = connectionManager;
        _metrics = metrics;
        _logSink = logSink;
        _scopeFactory = scopeFactory;
        _romajiConverter = romajiConverter;
        _logger = logger;

        LoadParagraphs();
    }

    private void LoadParagraphs()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "pvp_paragraphs.txt"),
            Path.Combine(Directory.GetCurrentDirectory(), "pvp_paragraphs.txt"),
            Path.Combine(Directory.GetCurrentDirectory(), "Data", "pvp_paragraphs.txt")
        };

        var foundPath = candidates.FirstOrDefault(File.Exists);
        if (foundPath != null)
        {
            foreach (var line in File.ReadAllLines(foundPath, Encoding.UTF8))
            {
                var trimmed = line.Trim();
                if (!string.IsNullOrEmpty(trimmed) && trimmed.Length <= 120)
                {
                    _paragraphs.Add(trimmed);
                }
            }
        }

        if (_paragraphs.Count == 0)
        {
            _paragraphs.AddRange(new[]
            {
                "日本語の勉強はとても面白いです。毎日少しずつ練習しましょう。",
                "桜の花が春に美しく咲きます。多くの人が花見を楽しみます。",
                "富士山は日本で一番高い山です。頂上からの景色は素晴らしいです。",
                "東京は世界で最も活気のある大都市の一つです。電車がとても便利です。",
                "美味しい寿司とラーメンを食べて、友達と一緒に日本語で会話しましょう。"
            });
        }

        _logger.LogInformation("[PvP Engine] Loaded {Count} paragraphs", _paragraphs.Count);
    }

    public async Task HandleJoinQueueAsync(long userId, string username)
    {
        // Cancel any existing match mapping
        LeaveQueue(userId);

        _logSink.Enqueue("PVP-ENGINE", "INFO", $"Player '{username}' (ID: {userId}) joined matchmaking queue");

        // Try to match with someone in queue
        while (_matchmakingQueue.TryDequeue(out var opponentId))
        {
            if (opponentId != userId && _connectionManager.TryGetSocket(opponentId, out _))
            {
                // Found eligible opponent
                await CreateMatchAsync(userId, username, opponentId);
                return;
            }
        }

        // No opponent yet, enqueue current user
        _matchmakingQueue.Enqueue(userId);
        await _connectionManager.SendToUserAsync(userId, new
        {
            @event = "queue_joined",
            status = "WAITING"
        });
    }

    public void LeaveQueue(long userId)
    {
        // Re-create queue without this user
        var items = _matchmakingQueue.ToArray();
        while (_matchmakingQueue.TryDequeue(out _)) { }
        foreach (var id in items)
        {
            if (id != userId) _matchmakingQueue.Enqueue(id);
        }
    }

    public async Task CreateLobbyAsync(long hostId, string hostName)
    {
        var code = "ROOM-" + _random.Next(1000, 9999);
        _lobbies[code] = (hostId, hostName);

        _logSink.Enqueue("PVP-ENGINE", "INFO", $"Lobby created: {code} by '{hostName}' (ID: {hostId})");

        await _connectionManager.SendToUserAsync(hostId, new
        {
            @event = "lobby_created",
            code = code
        });
    }

    public async Task JoinLobbyAsync(string code, long guestId, string guestName)
    {
        code = code.Trim().ToUpperInvariant();
        if (_lobbies.TryRemove(code, out var lobby))
        {
            if (lobby.HostId == guestId)
            {
                await _connectionManager.SendToUserAsync(guestId, new { @event = "error", message = "Cannot join own room" });
                return;
            }

            _logSink.Enqueue("PVP-ENGINE", "INFO", $"Player '{guestName}' joined room {code}. Starting 1v1 duel...");
            await CreateMatchAsync(lobby.HostId, lobby.HostName, guestId, guestName);
        }
        else
        {
            await _connectionManager.SendToUserAsync(guestId, new
            {
                @event = "error",
                message = "Room code not found or already in progress"
            });
        }
    }

    private async Task CreateMatchAsync(long p1Id, string p1Name, long p2Id, string? p2Name = null)
    {
        if (string.IsNullOrEmpty(p2Name))
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var p2User = await db.Users.FindAsync(p2Id);
            p2Name = p2User?.DisplayName ?? p2User?.Username ?? $"Player {p2Id}";
        }

        var paragraph = _paragraphs[_random.Next(_paragraphs.Count)];
        var romaji = await _romajiConverter.ToRomajiAsync(paragraph);
        if (string.IsNullOrEmpty(romaji)) romaji = paragraph;

        var match = new PvPMatchState
        {
            Player1Id = p1Id,
            Player1Name = p1Name,
            Player2Id = p2Id,
            Player2Name = p2Name,
            Paragraph = paragraph,
            Romaji = romaji
        };

        _activeMatches[match.MatchId] = match;
        _userMatchMap[p1Id] = match.MatchId;
        _userMatchMap[p2Id] = match.MatchId;

        _logSink.Enqueue("PVP-ENGINE", "MATCH", $"Duel #{match.MatchId} paired: '{p1Name}' vs '{p2Name}' (Len: {paragraph.Length} chars)");

        // Send match notifications to both players
        await _connectionManager.SendToUserAsync(p1Id, new
        {
            @event = "matched",
            matchId = match.MatchId,
            opponentId = p2Id,
            opponentName = p2Name,
            paragraph = match.Paragraph,
            romajiParagraph = match.Romaji,
            countdownMs = 3000
        });

        await _connectionManager.SendToUserAsync(p2Id, new
        {
            @event = "matched",
            matchId = match.MatchId,
            opponentId = p1Id,
            opponentName = p1Name,
            paragraph = match.Paragraph,
            romajiParagraph = match.Romaji,
            countdownMs = 3000
        });

        // Countdown timer in background
        _ = Task.Run(async () =>
        {
            await Task.Delay(3000);
            await _connectionManager.BroadcastAsync(new[] { p1Id, p2Id }, new
            {
                @event = "start",
                matchId = match.MatchId
            });
            _logSink.Enqueue("PVP-ENGINE", "START", $"Match #{match.MatchId} timer commenced! Realtime typing active.");
        });
    }

    public async Task HandleProgressSyncAsync(long userId, int progress)
    {
        if (!_userMatchMap.TryGetValue(userId, out var matchId) ||
            !_activeMatches.TryGetValue(matchId, out var match) ||
            match.IsFinished)
        {
            return;
        }

        long opponentId;
        string senderName;
        string opponentName;
        if (userId == match.Player1Id)
        {
            match.Player1Progress = progress;
            opponentId = match.Player2Id;
            senderName = match.Player1Name;
            opponentName = match.Player2Name;
        }
        else
        {
            match.Player2Progress = progress;
            opponentId = match.Player1Id;
            senderName = match.Player2Name;
            opponentName = match.Player1Name;
        }

        // Direct low-latency relay to opponent (<5ms)
        await _connectionManager.SendToUserAsync(opponentId, new
        {
            @event = "opp_progress",
            progress = progress
        });

        int totalLen = match.Paragraph.Length;
        int pct = totalLen > 0 ? Math.Min(100, (int)((progress / (double)totalLen) * 100)) : 0;
        _logSink.Enqueue("PVP-ENGINE", "PROGRESS", $"[Duel #{match.MatchId}] '{senderName}' ({progress}/{totalLen} chars - {pct}%) -> RELAY TO -> '{opponentName}' (UID: {opponentId})");
    }

    public async Task HandleFinishMatchAsync(long userId, long timeMs)
    {
        if (!_userMatchMap.TryGetValue(userId, out var matchId) ||
            !_activeMatches.TryGetValue(matchId, out var match))
        {
            return;
        }

        lock (match)
        {
            if (match.IsFinished) return;
            match.IsFinished = true;
            match.WinnerId = userId;
        }

        var isP1Winner = userId == match.Player1Id;
        var winnerName = isP1Winner ? match.Player1Name : match.Player2Name;
        var loserId = isP1Winner ? match.Player2Id : match.Player1Id;

        // Persist GCoin rewards
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var winner = await db.Users.FindAsync(userId);
            var loser = await db.Users.FindAsync(loserId);

            if (winner != null) winner.GCoin += 50;
            if (loser != null) loser.GCoin += 15;
            await db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to award GCoin for match #{MatchId}", match.MatchId);
        }

        _logSink.Enqueue("PVP-ENGINE", "FINISH", $"Match #{match.MatchId} FINISHED! Winner: '{winnerName}' in {timeMs / 1000.0:F2}s (+50 GCoin)");

        // Broadcast finish state to both players
        await _connectionManager.SendToUserAsync(userId, new
        {
            @event = "match_finished",
            winnerId = userId,
            winnerName = winnerName,
            isWinner = true,
            reward = 50
        });

        await _connectionManager.SendToUserAsync(loserId, new
        {
            @event = "match_finished",
            winnerId = userId,
            winnerName = winnerName,
            isWinner = false,
            reward = 15
        });

        _userMatchMap.TryRemove(match.Player1Id, out _);
        _userMatchMap.TryRemove(match.Player2Id, out _);
        _activeMatches.TryRemove(matchId, out _);
    }

    public async Task HandleDisconnectAsync(long userId)
    {
        LeaveQueue(userId);

        if (_userMatchMap.TryRemove(userId, out var matchId) &&
            _activeMatches.TryRemove(matchId, out var match) &&
            !match.IsFinished)
        {
            match.IsFinished = true;
            var remainingId = (userId == match.Player1Id) ? match.Player2Id : match.Player1Id;
            var leaverName = (userId == match.Player1Id) ? match.Player1Name : match.Player2Name;

            _logSink.Enqueue("PVP-ENGINE", "WARN", $"Match #{match.MatchId}: Player '{leaverName}' disconnected. Awarding win to remaining opponent.");

            await _connectionManager.SendToUserAsync(remainingId, new
            {
                @event = "opponent_left",
                message = "Opponent disconnected. You win by forfeit!",
                winnerId = remainingId,
                reward = 35
            });

            _userMatchMap.TryRemove(remainingId, out _);
        }
    }
}
