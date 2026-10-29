namespace JapaneseMasteryBackendDotNet.DTOs;

public class CustomTestResponse
{
    public long Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string TestCode { get; set; } = string.Empty;
    public int MinLevel { get; set; }
    public int RewardGcoin { get; set; }
    public int MaxAttempts { get; set; }
    public bool IsApproved { get; set; }
    public long SenseiId { get; set; }
    public string SenseiUsername { get; set; } = string.Empty;
    public List<CustomTestQuestionDTO> Questions { get; set; } = new();
}

