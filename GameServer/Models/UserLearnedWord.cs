using System.Text.Json.Serialization;

namespace JapaneseMasteryBackendDotNet.Models;

public class UserLearnedWord
{
    public long UserId { get; set; }
    public string WordJp { get; set; } = string.Empty;

    [JsonIgnore]
    public User? User { get; set; }
}

