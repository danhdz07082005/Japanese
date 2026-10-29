using System.Text.Json.Serialization;

namespace JapaneseMasteryBackendDotNet.Models;

public class Vocabulary
{
    public long Id { get; set; }

    public string WordJp { get; set; } = string.Empty;

    public string? Kana { get; set; }

    public string Romaji { get; set; } = string.Empty;

    public string Meaning { get; set; } = string.Empty;

    public int LevelRequired { get; set; }

    public int Level => LevelRequired;

    public WordType Type { get; set; } = WordType.HIRAGANA;
}

