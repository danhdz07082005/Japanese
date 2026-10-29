using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Services;

public class VocabularyService
{
    private readonly AppDbContext _context;
    private readonly JMdictService _jmdictService;

    public VocabularyService(AppDbContext context, JMdictService jmdictService)
    {
        _context = context;
        _jmdictService = jmdictService;
    }

    public List<Vocabulary> GetAllVocabularies()
    {
        var vocabs = _jmdictService.GetAllVocabularies();
        if (vocabs.Count == 0)
        {
            vocabs = _context.Vocabularies.AsNoTracking().ToList();
        }
        return vocabs;
    }

    public async Task<Vocabulary> GetVocabularyByIdAsync(long id)
    {
        var vocab = await _context.Vocabularies.FindAsync(id);
        if (vocab == null)
        {
            throw new InvalidOperationException("Vocabulary not found");
        }
        return vocab;
    }

    public async Task<Vocabulary> UpdateVocabularyLevelAsync(long id, int level)
    {
        var vocab = await GetVocabularyByIdAsync(id);
        vocab.LevelRequired = level;
        await _context.SaveChangesAsync();
        return vocab;
    }

    public List<Vocabulary> GetVocabulariesForLevel(int level, IEnumerable<string>? learnedWords = null)
    {
        var baseList = _jmdictService.GetVocabulariesForLevel(level);
        if (baseList.Count == 0)
        {
            baseList = _context.Vocabularies.AsNoTracking().Where(v => v.LevelRequired == level).ToList();
        }

        var expandedList = new List<Vocabulary>();

        foreach (var v in baseList)
        {
            var wordJp = !string.IsNullOrEmpty(v.WordJp) ? v.WordJp : v.Kana ?? string.Empty;
            var kana = !string.IsNullOrEmpty(v.Kana) ? v.Kana : v.WordJp ?? string.Empty;

            if (HasKanji(wordJp))
            {
                // Add Kanji version
                expandedList.Add(new Vocabulary
                {
                    Id = v.Id,
                    WordJp = wordJp,
                    Kana = kana,
                    Romaji = v.Romaji,
                    Meaning = v.Meaning,
                    Type = v.Type,
                    LevelRequired = v.LevelRequired
                });

                // Add Kana version
                expandedList.Add(new Vocabulary
                {
                    Id = v.Id,
                    WordJp = kana,
                    Kana = kana,
                    Romaji = v.Romaji,
                    Meaning = v.Meaning,
                    Type = v.Type,
                    LevelRequired = v.LevelRequired
                });
            }
            else
            {
                // Just add as is (Hiragana/Katakana)
                expandedList.Add(new Vocabulary
                {
                    Id = v.Id,
                    WordJp = wordJp,
                    Kana = kana,
                    Romaji = v.Romaji,
                    Meaning = v.Meaning,
                    Type = v.Type,
                    LevelRequired = v.LevelRequired
                });
            }
        }

        return expandedList;
    }

    private static bool HasKanji(string? s)
    {
        if (string.IsNullOrEmpty(s)) return false;
        foreach (var c in s)
        {
            if (c >= '\u4e00' && c <= '\u9faf') return true;
        }
        return false;
    }
}
