using System.Text.Json.Serialization;
using JapaneseMasteryBackendDotNet.Models;

namespace JapaneseMasteryBackendDotNet.DTOs;

public class AuthResponse
{
    public long Id { get; set; }
    public string Token { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public Role Role { get; set; }
    public int Level { get; set; }

    [JsonPropertyName("gCoin")]
    public int GCoin { get; set; }

    public long? ActiveThemeId { get; set; }
    public string? ActiveThemeUrl { get; set; }
    public List<long> PurchasedItemIds { get; set; } = new();
}

