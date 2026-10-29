using System.Text.Json.Serialization;

namespace JapaneseMasteryBackendDotNet.Models;

public class User
{
    public long Id { get; set; }

    public string Username { get; set; } = string.Empty;

    [JsonIgnore]
    public string Password { get; set; } = string.Empty;

    public Role Role { get; set; } = Role.PLAYER;

    public int Level { get; set; } = 1;

    [JsonPropertyName("gCoin")]
    public int GCoin { get; set; } = 0;

    public string? DisplayName { get; set; }

    public string? AccessToken { get; set; }

    public DateTime? PvpBanUntil { get; set; }

    [JsonIgnore]
    public ICollection<UserLearnedWord> UserLearnedWords { get; set; } = new List<UserLearnedWord>();

    public IEnumerable<string> LearnedWords => UserLearnedWords.Select(w => w.WordJp);

    public ICollection<ShopItem> PurchasedItems { get; set; } = new List<ShopItem>();

    public long? ActiveThemeId { get; set; }
    public ShopItem? ActiveTheme { get; set; }

    public long? ActiveBackgroundId { get; set; }
    public ShopItem? ActiveBackground { get; set; }
}

