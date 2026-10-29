namespace JapaneseMasteryBackendDotNet.DTOs;

public class CustomTestAttemptDTO
{
    public string PlayerName { get; set; } = string.Empty;
    public int Score { get; set; }
    public bool Passed { get; set; }
    public DateTime? AttemptTime { get; set; }
}

