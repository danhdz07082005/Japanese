using System.Text.Json.Serialization;

namespace JapaneseMasteryBackendDotNet.Models;

public class CustomTestQuestion
{
    public long Id { get; set; }

    public long CustomTestId { get; set; }

    [JsonIgnore]
    public CustomTest? CustomTest { get; set; }

    public string QuestionText { get; set; } = string.Empty;
    public string? AnswerA { get; set; }
    public string? AnswerB { get; set; }
    public string? AnswerC { get; set; }
    public string? AnswerD { get; set; }
    public string CorrectAnswer { get; set; } = string.Empty;
}

