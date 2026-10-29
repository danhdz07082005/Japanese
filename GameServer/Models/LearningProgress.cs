using System.Text.Json.Serialization;

namespace JapaneseMasteryBackendDotNet.Models;

public class LearningProgress
{
    public long Id { get; set; }

    public long UserId { get; set; }

    [JsonIgnore]
    public User? User { get; set; }

    public string? WordJp { get; set; }

    public long? VocabularyId { get; set; }

    public bool IsMemorized { get; set; }
    public int HesitationCount { get; set; }
    public DateTime? LastReviewTime { get; set; }
    public bool IsWritingPassed { get; set; }
}

