using System.Text.Json.Serialization;

namespace JapaneseMasteryBackendDotNet.Models;

public class CustomTest
{
    public long Id { get; set; }
    public string Title { get; set; } = string.Empty;

    public long SenseiId { get; set; }

    [JsonIgnore]
    public User? Sensei { get; set; }

    public string TestCode { get; set; } = string.Empty;
    public int MinLevel { get; set; } = 1;
    public int RewardGcoin { get; set; }
    public int MaxAttempts { get; set; }
    public bool IsApproved { get; set; } = true;

    public ICollection<CustomTestQuestion> Questions { get; set; } = new List<CustomTestQuestion>();
}

