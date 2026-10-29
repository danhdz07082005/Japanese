using System.Text.Json.Serialization;

namespace JapaneseMasteryBackendDotNet.Models;

public class CustomTestAttempt
{
    public long Id { get; set; }

    public long PlayerId { get; set; }

    [JsonIgnore]
    public User? Player { get; set; }

    public long TestId { get; set; }

    [JsonIgnore]
    public CustomTest? Test { get; set; }

    public int Score { get; set; }
    public bool Passed { get; set; }
    public DateTime? AttemptTime { get; set; }
}

