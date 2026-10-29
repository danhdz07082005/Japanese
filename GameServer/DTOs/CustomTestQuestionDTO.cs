namespace JapaneseMasteryBackendDotNet.DTOs;

public class CustomTestQuestionDTO
{
    public long? Id { get; set; }
    public string QuestionText { get; set; } = string.Empty;
    public string? AnswerA { get; set; }
    public string? AnswerB { get; set; }
    public string? AnswerC { get; set; }
    public string? AnswerD { get; set; }
    public string CorrectAnswer { get; set; } = string.Empty;
}

