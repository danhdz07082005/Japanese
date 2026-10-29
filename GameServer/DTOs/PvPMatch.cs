namespace JapaneseMasteryBackendDotNet.DTOs;

public class PvPMatch
{
    public string MatchId { get; set; } = string.Empty;
    public long Player1Id { get; set; }
    public long Player2Id { get; set; }
    public string Paragraph { get; set; } = string.Empty;
    public string RomajiParagraph { get; set; } = string.Empty;
    public string State { get; set; } = "WAITING_P1"; // "WAITING_P1", "WAITING_P2", "COUNTDOWN", "PLAYING", "FINISHED"

    public long P1TimeMs { get; set; } = 0;
    public long P2TimeMs { get; set; } = 0;

    public long WinnerId { get; set; } = -1;
    public int GCoinReward { get; set; } = 100;

    public long StartTimeMs { get; set; } = 0;
}

