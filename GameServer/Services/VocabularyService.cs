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
        int oldLevel = vocab.LevelRequired;
        vocab.LevelRequired = level;
        await _context.SaveChangesAsync();
        _jmdictService.UpdateVocabularyLevel(id, oldLevel, level, vocab);
        return vocab;
    }

    public List<Vocabulary> GetVocabulariesForLevel(int level, IEnumerable<string>? learnedWords = null)
    {
        var baseList = _jmdictService.GetVocabulariesForLevel(level);
        if (baseList.Count == 0)
        {
            baseList = _context.Vocabularies.AsNoTracking().Where(v => v.LevelRequired == level).ToList();
        }

        return baseList;
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
