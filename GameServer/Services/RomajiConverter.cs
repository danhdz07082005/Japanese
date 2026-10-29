using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;

namespace JapaneseMasteryBackendDotNet.Services;

public class RomajiConverter
{
    private static readonly ConcurrentDictionary<string, string> Cache = new();
    private readonly HttpClient _httpClient;
    private readonly string _kuroshiroUrl;
    private readonly ILogger<RomajiConverter> _logger;

    public RomajiConverter(HttpClient httpClient, IConfiguration config, ILogger<RomajiConverter> logger)
    {
        _httpClient = httpClient;
        _kuroshiroUrl = config["App:KuroshiroUrl"] ?? "http://localhost:8081/convert";
        _logger = logger;
    }

    public async Task<string> ToRomajiAsync(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;

        if (Cache.TryGetValue(text, out var cached))
        {
            return cached;
        }

        try
        {
            var payload = JsonSerializer.Serialize(new { text });
            using var content = new StringContent(payload, Encoding.UTF8, "application/json");

            var response = await _httpClient.PostAsync(_kuroshiroUrl, content);
            if (response.IsSuccessStatusCode)
            {
                var jsonStr = await response.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(jsonStr);
                if (doc.RootElement.TryGetProperty("romaji", out var romajiProp))
                {
                    var romaji = romajiProp.GetString() ?? string.Empty;

                    // Convert Hepburn macrons to Wapuro typing format
                    romaji = romaji.Replace("ā", "aa")
                                   .Replace("ī", "ii")
                                   .Replace("ū", "uu")
                                   .Replace("ē", "ee")
                                   .Replace("ō", "ou")
                                   .Replace("〜", "~")
                                   .Replace("～", "~");

                    Cache[text] = romaji;
                    return romaji;
                }
            }

            _logger.LogWarning("Kuroshiro microservice responded with status {StatusCode}", response.StatusCode);
            return text;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to connect to Kuroshiro Microservice at {Url}", _kuroshiroUrl);
            return text;
        }
    }
}

