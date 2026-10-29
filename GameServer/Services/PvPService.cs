using System.Collections.Concurrent;
using System.Text;
using System.Text.RegularExpressions;
using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Services;

public class PvPService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly JMdictService _jmdictService;
    private readonly RomajiConverter _romajiConverter;
    private readonly ILogger<PvPService> _logger;

    private readonly List<string> _paragraphs = new();
    private readonly Random _random = new();

    private ConcurrentQueue<long> _queueUnder25 = new();
    private ConcurrentQueue<long> _queueOver24 = new();

    private readonly ConcurrentDictionary<string, PvPMatch> _activeMatches = new();
    private readonly ConcurrentDictionary<long, string> _userMatchMap = new();
    private readonly ConcurrentDictionary<string, long> _lobbies = new();

    private readonly object _queueLock = new();

    public PvPService(
        IServiceScopeFactory scopeFactory,
        JMdictService jmdictService,
        RomajiConverter romajiConverter,
        ILogger<PvPService> logger)
    {
        _scopeFactory = scopeFactory;
        _jmdictService = jmdictService;
        _romajiConverter = romajiConverter;
        _logger = logger;

        InitParagraphs();
    }

    private void InitParagraphs()
    {
        try
        {
            var baseDir = Directory.GetCurrentDirectory();
            var dirInfo = new DirectoryInfo(baseDir);
            if (dirInfo.Name.Equals("JapaneseMasteryBackendDotNet", StringComparison.OrdinalIgnoreCase) ||
                dirInfo.Name.Equals("JapaneseMasteryBackend", StringComparison.OrdinalIgnoreCase))
            {
                baseDir = dirInfo.Parent?.FullName ?? baseDir;
            }

            var candidates = new[]
            {
                Path.Combine(AppContext.BaseDirectory, "pvp_paragraphs.txt"),
                Path.Combine(Directory.GetCurrentDirectory(), "pvp_paragraphs.txt"),
                Path.Combine(baseDir, "JapaneseMasteryBackendDotNet", "pvp_paragraphs.txt"),
                Path.Combine(baseDir, "JapaneseMasteryBackend", "pvp_paragraphs.txt"),
                Path.Combine(baseDir, "pvp_paragraphs.txt")
            };

            string? filePath = candidates.FirstOrDefault(File.Exists);
            if (filePath != null)
            {
                foreach (var line in File.ReadAllLines(filePath, Encoding.UTF8))
                {
                    var trimmed = SanitizeWikiText(line.Trim());
                    if (!string.IsNullOrEmpty(trimmed) && trimmed.Length <= 150)
                    {
                        _paragraphs.Add(trimmed);
                    }
                }
                _logger.LogInformation("Loaded {Count} PvP paragraphs from {Path}", _paragraphs.Count, filePath);
            }
            else
            {
                _logger.LogWarning("pvp_paragraphs.txt not found in any candidate path.");
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load PvP paragraphs file.");
        }

        if (_paragraphs.Count == 0)
        {
            _paragraphs.Add("これはテストの文章です。");
        }
    }

    private static string SanitizeWikiText(string? text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;

        // Remove common wiki artifacts
        text = Regex.Replace(text, @"\{\{.*?\}\}", "");
        text = Regex.Replace(text, @"\[\[(.*?\|)?(.*?)\]\]", "$2");
        text = Regex.Replace(text, @"<ref.*?>.*?</ref>", "");
        text = Regex.Replace(text, @"<.*?>", "");
        text = text.Replace("\r", "").Replace("\n", " ");

        var sb = new StringBuilder();
        foreach (var c in text)
        {
            if ((c >= 0x00 && c <= 0x7F) || // ASCII
                (c >= 0x3000 && c <= 0x303F) || // JP Punctuation
                (c >= 0x3040 && c <= 0x309F) || // Hiragana
                (c >= 0x30A0 && c <= 0x30FF) || // Katakana
                (c >= 0x4E00 && c <= 0x9FAF) || // Kanji
                (c >= 0xFF00 && c <= 0xFFEF))   // Full-width
            {
                sb.Append(c);
            }
        }
        return sb.ToString().Trim();
    }

    public async Task<string> JoinQueueAsync(long userId)
    {
        lock (_queueLock)
        {
            if (_userMatchMap.TryGetValue(userId, out var matchId))
            {
                if (_activeMatches.TryGetValue(matchId, out var match) && "FINISHED".Equals(match.State, StringComparison.OrdinalIgnoreCase))
                {
                    AcknowledgeFinish(userId);
                }
                else if (match != null)
                {
                    return "ALREADY_IN_MATCH";
                }
            }
        }

        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = await context.Users.FindAsync(userId);
        if (user == null) return "ERROR";

        if (user.PvpBanUntil.HasValue && user.PvpBanUntil.Value > DateTime.UtcNow)
        {
            return "BANNED";
        }

        lock (_queueLock)
        {
            if (user.Level < 25)
            {
                if (!_queueUnder25.Contains(userId))
                {
                    _queueUnder25.Enqueue(userId);
                }
            }
            else
            {
                if (!_queueOver24.Contains(userId))
                {
                    _queueOver24.Enqueue(userId);
                }
            }
        }

        return "QUEUED";
    }

    public void LeaveQueue(long userId)
    {
        lock (_queueLock)
        {
            _queueUnder25 = new ConcurrentQueue<long>(_queueUnder25.Where(id => id != userId));
            _queueOver24 = new ConcurrentQueue<long>(_queueOver24.Where(id => id != userId));
        }
    }

    public async Task MatchPlayersAsync()
    {
        await ProcessQueueUnder25Async();
        await ProcessQueueOver24Async();
    }

    private async Task ProcessQueueUnder25Async()
    {
        while (true)
        {
            long p1;
            lock (_queueLock)
            {
                if (!_queueUnder25.TryDequeue(out p1)) break;
            }

            var matchId = Guid.NewGuid().ToString();
            var match = new PvPMatch
            {
                MatchId = matchId,
                Player1Id = p1,
                Player2Id = -1, // BOT
                State = "COUNTDOWN",
                P1TimeMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + 3000
            };

            var jp = GetRandomWordsJp(20);
            if (string.IsNullOrWhiteSpace(jp)) jp = "テスト 単語";
            match.Paragraph = jp;

            var rp = await _romajiConverter.ToRomajiAsync(jp);
            if (string.IsNullOrWhiteSpace(rp) || rp == "error") rp = jp;
            match.RomajiParagraph = rp.Replace("〜", "~").Replace("～", "~");

            _activeMatches[matchId] = match;
            _userMatchMap[p1] = matchId;
        }
    }

    private async Task ProcessQueueOver24Async()
    {
        while (true)
        {
            long p1, p2;
            lock (_queueLock)
            {
                if (_queueOver24.Count < 2) break;
                if (!_queueOver24.TryDequeue(out p1)) break;
                if (!_queueOver24.TryDequeue(out p2))
                {
                    _queueOver24.Enqueue(p1);
                    break;
                }
            }

            var matchId = Guid.NewGuid().ToString();
            var match = new PvPMatch
            {
                MatchId = matchId,
                Player1Id = p1,
                Player2Id = p2,
                State = "COUNTDOWN",
                P1TimeMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + 3000
            };

            var p = GetRandomParagraph();
            if (string.IsNullOrWhiteSpace(p)) p = "これはテストの文章です。";
            p = p.Replace("\r", "").Replace("\n", " ").Trim();
            match.Paragraph = p;

            var rp = await _romajiConverter.ToRomajiAsync(p);
            if (string.IsNullOrWhiteSpace(rp) || rp == "error") rp = p;
            match.RomajiParagraph = rp.Replace("〜", "~").Replace("～", "~");

            _activeMatches[matchId] = match;
            _userMatchMap[p1] = matchId;
            _userMatchMap[p2] = matchId;
        }
    }

    private string GetRandomParagraph()
    {
        if (_paragraphs.Count == 0) return "エラー";
        return _paragraphs[_random.Next(_paragraphs.Count)];
    }

    private string GetRandomWordsJp(int count)
    {
        var all = _jmdictService.GetAllVocabularies();
        var valid = all.Where(v => v.LevelRequired <= 24).ToList();
        if (valid.Count == 0)
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                valid = context.Vocabularies.AsNoTracking().Where(v => v.LevelRequired <= 24).ToList();
            }
            catch { }
        }

        if (valid.Count == 0) return "テスト 単語";

        var shuffled = valid.OrderBy(_ => _random.Next()).Take(count);
        return string.Join(" ", shuffled.Select(v => !string.IsNullOrEmpty(v.WordJp) ? v.WordJp : v.Kana ?? string.Empty));
    }

    public async Task<Dictionary<string, object>> GetStatusAsync(long userId)
    {
        var response = new Dictionary<string, object>();

        if (!_userMatchMap.TryGetValue(userId, out var matchId))
        {
            lock (_queueLock)
            {
                if (_queueUnder25.Contains(userId) || _queueOver24.Contains(userId))
                {
                    response["status"] = "QUEUED";
                }
                else
                {
                    response["status"] = "NONE";
                }
            }
            return response;
        }

        if (!_activeMatches.TryGetValue(matchId, out var match) || match == null)
        {
            _userMatchMap.TryRemove(userId, out _);
            response["status"] = "NONE";
            return response;
        }

        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        // Check countdown
        if ("COUNTDOWN".Equals(match.State, StringComparison.OrdinalIgnoreCase))
        {
            var remaining = match.P1TimeMs - nowMs;
            if (remaining <= 0)
            {
                match.State = "PLAYING";
                match.P1TimeMs = 0;
                match.P2TimeMs = 0;
                match.StartTimeMs = nowMs;
            }
            else
            {
                response["countdown"] = remaining;
            }
        }
        else if ("PLAYING".Equals(match.State, StringComparison.OrdinalIgnoreCase) && match.Player2Id == -1)
        {
            // Simulate bot progress
            var elapsed = nowMs - match.StartTimeMs;
            var botProgress = (int)(elapsed / 333);
            if (botProgress > match.RomajiParagraph.Length)
            {
                botProgress = match.RomajiParagraph.Length;
            }
            match.P2TimeMs = botProgress;

            if (botProgress == match.RomajiParagraph.Length)
            {
                await FinishMatchByMatchIdAsync(-1, matchId);
            }
        }

        response["status"] = "MATCHED";
        response["matchId"] = match.MatchId;
        response["paragraph"] = match.Paragraph;
        response["romajiParagraph"] = match.RomajiParagraph;
        response["state"] = match.State;

        var isP1 = userId == match.Player1Id;
        var opponentId = isP1 ? match.Player2Id : match.Player1Id;
        response["opponentId"] = opponentId;

        if (opponentId == -1)
        {
            response["opponentName"] = "BOT";
        }
        else
        {
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var opponent = await context.Users.FindAsync(opponentId);
            response["opponentName"] = opponent?.Username ?? "Opponent";
        }

        response["myProgress"] = isP1 ? match.P1TimeMs : match.P2TimeMs;
        response["oppProgress"] = isP1 ? match.P2TimeMs : match.P1TimeMs;

        if ("FINISHED".Equals(match.State, StringComparison.OrdinalIgnoreCase))
        {
            response["winnerId"] = match.WinnerId;
            response["reward"] = match.GCoinReward;
        }

        return response;
    }

    public string UpdateProgress(long userId, int progress)
    {
        if (!_userMatchMap.TryGetValue(userId, out var matchId)) return "NO_MATCH";
        if (!_activeMatches.TryGetValue(matchId, out var match) || !"PLAYING".Equals(match.State, StringComparison.OrdinalIgnoreCase)) return "NOT_PLAYING";

        if (userId == match.Player1Id) match.P1TimeMs = progress;
        else if (userId == match.Player2Id) match.P2TimeMs = progress;

        return "OK";
    }

    public async Task<string> FinishMatchAsync(long userId, long timeTaken)
    {
        if (!_userMatchMap.TryGetValue(userId, out var matchId)) return "NO_MATCH";
        return await FinishMatchByMatchIdAsync(userId, matchId);
    }

    public async Task<string> FinishMatchByMatchIdAsync(long winnerId, string matchId)
    {
        if (!_activeMatches.TryGetValue(matchId, out var match) || !"PLAYING".Equals(match.State, StringComparison.OrdinalIgnoreCase)) return "NOT_PLAYING";

        match.State = "FINISHED";
        match.WinnerId = winnerId;

        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Reward winner
        if (winnerId != -1)
        {
            var winner = await context.Users.FindAsync(winnerId);
            if (winner != null)
            {
                winner.GCoin += 100;
            }
        }

        // Punish loser
        var loserId = winnerId == match.Player1Id ? match.Player2Id : match.Player1Id;
        if (loserId != -1)
        {
            var loser = await context.Users.FindAsync(loserId);
            if (loser != null)
            {
                if (loser.GCoin >= 100)
                {
                    loser.GCoin -= 100;
                }
                else
                {
                    loser.GCoin = 0;
                    loser.PvpBanUntil = DateTime.UtcNow.AddHours(1);
                }
            }
        }

        await context.SaveChangesAsync();
        return "FINISHED";
    }

    public async Task<string> QuitMatchAsync(long userId)
    {
        if (!_userMatchMap.TryGetValue(userId, out var matchId)) return "NO_MATCH";
        if (!_activeMatches.TryGetValue(matchId, out var match)) return "NO_MATCH";
        if ("FINISHED".Equals(match.State, StringComparison.OrdinalIgnoreCase)) return "ALREADY_FINISHED";

        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Punish quitter
        var quitter = await context.Users.FindAsync(userId);
        if (quitter != null)
        {
            if (quitter.GCoin >= 100)
            {
                quitter.GCoin -= 100;
            }
            else
            {
                quitter.GCoin = 0;
            }
            quitter.PvpBanUntil = DateTime.UtcNow.AddHours(1);
        }

        // Award opponent
        var opponentId = userId == match.Player1Id ? match.Player2Id : match.Player1Id;
        if (opponentId != -1)
        {
            var opponent = await context.Users.FindAsync(opponentId);
            if (opponent != null)
            {
                opponent.GCoin += 100;
            }
        }

        await context.SaveChangesAsync();

        match.WinnerId = opponentId;
        match.State = "FINISHED";

        return "QUIT_SUCCESS";
    }

    public void AcknowledgeFinish(long userId)
    {
        if (_userMatchMap.TryRemove(userId, out var matchId))
        {
            if (_activeMatches.TryGetValue(matchId, out var match) && "FINISHED".Equals(match.State, StringComparison.OrdinalIgnoreCase))
            {
                var opponentId = userId == match.Player1Id ? match.Player2Id : match.Player1Id;
                if (!_userMatchMap.ContainsKey(opponentId))
                {
                    _activeMatches.TryRemove(matchId, out _);
                }
            }
        }
    }

    // ============ LOBBY SYSTEM ============

    public async Task<Dictionary<string, object>> CreateLobbyAsync(long userId)
    {
        var response = new Dictionary<string, object>();

        if (_userMatchMap.TryGetValue(userId, out var matchId))
        {
            if (_activeMatches.TryGetValue(matchId, out var match) && !"FINISHED".Equals(match.State, StringComparison.OrdinalIgnoreCase))
            {
                response["error"] = "ALREADY_IN_MATCH";
                return response;
            }
            AcknowledgeFinish(userId);
        }

        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = await context.Users.FindAsync(userId);
        if (user == null)
        {
            response["error"] = "USER_NOT_FOUND";
            return response;
        }

        if (user.PvpBanUntil.HasValue && user.PvpBanUntil.Value > DateTime.UtcNow)
        {
            response["error"] = "BANNED";
            return response;
        }

        // Remove any existing lobby by this user
        foreach (var pair in _lobbies.Where(e => e.Value == userId).ToList())
        {
            _lobbies.TryRemove(pair.Key, out _);
        }

        var code = GenerateLobbyCode();
        while (_lobbies.ContainsKey(code))
        {
            code = GenerateLobbyCode();
        }

        _lobbies[code] = userId;
        response["lobbyCode"] = code;
        response["status"] = "LOBBY_CREATED";
        return response;
    }

    public async Task<Dictionary<string, object>> JoinLobbyAsync(string code, long userId)
    {
        var response = new Dictionary<string, object>();
        var upperCode = code.ToUpperInvariant();

        if (!_lobbies.TryGetValue(upperCode, out var hostId))
        {
            response["error"] = "LOBBY_NOT_FOUND";
            return response;
        }

        if (hostId == userId)
        {
            response["error"] = "CANNOT_JOIN_OWN_LOBBY";
            return response;
        }

        if (_userMatchMap.TryGetValue(userId, out var existingMatch))
        {
            if (_activeMatches.TryGetValue(existingMatch, out var em) && !"FINISHED".Equals(em.State, StringComparison.OrdinalIgnoreCase))
            {
                response["error"] = "ALREADY_IN_MATCH";
                return response;
            }
            AcknowledgeFinish(userId);
        }

        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var joiner = await context.Users.FindAsync(userId);
        if (joiner == null)
        {
            response["error"] = "USER_NOT_FOUND";
            return response;
        }

        if (joiner.PvpBanUntil.HasValue && joiner.PvpBanUntil.Value > DateTime.UtcNow)
        {
            response["error"] = "BANNED";
            return response;
        }

        _lobbies.TryRemove(upperCode, out _);

        LeaveQueue(hostId);
        LeaveQueue(userId);

        var matchId = Guid.NewGuid().ToString();
        var match = new PvPMatch
        {
            MatchId = matchId,
            Player1Id = hostId,
            Player2Id = userId,
            State = "COUNTDOWN",
            P1TimeMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + 3000
        };

        var p = GetRandomParagraph();
        if (string.IsNullOrWhiteSpace(p)) p = "これはテストの文章です。";
        p = p.Replace("\r", "").Replace("\n", " ").Trim();
        match.Paragraph = p;

        var rp = await _romajiConverter.ToRomajiAsync(p);
        if (string.IsNullOrWhiteSpace(rp) || rp == "error") rp = p;
        match.RomajiParagraph = rp.Replace("〜", "~").Replace("～", "~");

        _activeMatches[matchId] = match;
        _userMatchMap[hostId] = matchId;
        _userMatchMap[userId] = matchId;

        response["status"] = "MATCH_CREATED";
        response["matchId"] = matchId;
        return response;
    }

    public void CancelLobby(string code, long userId)
    {
        var upperCode = code.ToUpperInvariant();
        if (_lobbies.TryGetValue(upperCode, out var hostId) && hostId == userId)
        {
            _lobbies.TryRemove(upperCode, out _);
        }
    }

    private string GenerateLobbyCode()
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var sb = new StringBuilder();
        for (int i = 0; i < 6; i++)
        {
            sb.Append(chars[_random.Next(chars.Length)]);
        }
        return sb.ToString();
    }
}

