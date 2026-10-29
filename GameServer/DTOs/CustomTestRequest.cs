namespace JapaneseMasteryBackendDotNet.DTOs;

public class CustomTestRequest
{
    public string Title { get; set; } = string.Empty;
    public string? TestCode { get; set; }
    public int? MinLevel { get; set; }
    public int? RewardGcoin { get; set; }
    public int? MaxAttempts { get; set; }
    public List<CustomTestQuestionDTO>? Questions { get; set; }
}

