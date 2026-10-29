using System.Text.Json;
using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Services;

public class JMdictService
{
    private readonly Dictionary<int, List<Vocabulary>> _levelVocabMap = new();
    private readonly object _lock = new();
    private readonly ILogger<JMdictService> _logger;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IHttpClientFactory _httpClientFactory;

    public JMdictService(
        IServiceScopeFactory scopeFactory,
        IHttpClientFactory httpClientFactory,
        ILogger<JMdictService> logger)
    {
        _scopeFactory = scopeFactory;
        _httpClientFactory = httpClientFactory;
        _logger = logger;

        ReloadJMdict();
    }

    public void ReloadJMdict()
    {
        lock (_lock)
        {
            try
            {
                _levelVocabMap.Clear();

                // 1. Primary Source: Load from Database (Levels 1-24 and any previously seeded/stored words)
                try
                {
                    using var scope = _scopeFactory.CreateScope();
                    var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                    var dbVocabs = context.Vocabularies.ToList();
                    bool dbUpdated = false;
                    foreach (var v in dbVocabs)
                    {
                        if (v.LevelRequired >= 25 && (string.IsNullOrEmpty(v.Romaji) || v.Romaji == v.Kana))
                        {
                            v.Romaji = ConvertKanaToRomaji(v.Kana ?? v.WordJp ?? "");
                            dbUpdated = true;
                        }

                        if (!_levelVocabMap.TryGetValue(v.LevelRequired, out var list))
                        {
                            list = new List<Vocabulary>();
                            _levelVocabMap[v.LevelRequired] = list;
                        }
                        list.Add(v);
                    }
                    if (dbUpdated)
                    {
                        try { context.SaveChanges(); } catch { }
                    }

                    if (dbVocabs.Count > 0)
                    {
                        _logger.LogInformation("Loaded {Count} vocabularies from Database across {Levels} levels.", dbVocabs.Count, _levelVocabMap.Count);
                    }
                }
                catch (Exception dbEx)
                {
                    _logger.LogWarning("Database not ready during initial JMdictService load: {Message}", dbEx.Message);
                }

                // 2. Secondary Source: JSON file discovery across known workspace paths
                var baseDir = Directory.GetCurrentDirectory();
                var dirInfo = new DirectoryInfo(baseDir);
                if (dirInfo.Name.Equals("JapaneseMasteryBackendDotNet", StringComparison.OrdinalIgnoreCase) ||
                    dirInfo.Name.Equals("JapaneseMasteryBackend", StringComparison.OrdinalIgnoreCase))
                {
                    baseDir = dirInfo.Parent?.FullName ?? baseDir;
                }

                var options = new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                };

                var searchPaths = new[]
                {
                    AppContext.BaseDirectory,
                    Directory.GetCurrentDirectory(),
                    Path.Combine(baseDir, "JapaneseMastery", "data"),
                    Path.Combine(baseDir, "data"),
                    Path.Combine(baseDir, "JapaneseMasteryUnity", "Assets", "StreamingAssets", "data")
                };

                foreach (var folder in searchPaths)
                {
                    if (!Directory.Exists(folder)) continue;

                    var defaultJsonFile = Path.Combine(folder, "default_vocab.json");
                    if (File.Exists(defaultJsonFile))
                    {
                        try
                        {
                            var json = File.ReadAllText(defaultJsonFile);
                            var defaultMap = JsonSerializer.Deserialize<Dictionary<string, List<Vocabulary>>>(json, options);
                            if (defaultMap != null)
                            {
                                foreach (var (k, v) in defaultMap)
                                {
                                    if (int.TryParse(k, out var lvl) && !_levelVocabMap.ContainsKey(lvl))
                                    {
                                        _levelVocabMap[lvl] = v;
                                    }
                                }
                            }
                        }
                        catch { }
                    }

                    var levelsJsonFile = Path.Combine(folder, "jmdict_levels.json");
                    if (File.Exists(levelsJsonFile))
                    {
                        try
                        {
                            var json = File.ReadAllText(levelsJsonFile);
                            var levelsMap = JsonSerializer.Deserialize<Dictionary<string, List<Vocabulary>>>(json, options);
                            if (levelsMap != null)
                            {
                                foreach (var (k, v) in levelsMap)
                                {
                                    if (int.TryParse(k, out var lvl) && !_levelVocabMap.ContainsKey(lvl))
                                    {
                                        _levelVocabMap[lvl] = v;
                                    }
                                }
                            }
                        }
                        catch { }
                    }
                }

                _logger.LogInformation("JMdictService ready with {Count} total levels available.", _levelVocabMap.Count);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to initialize JMdictService.");
            }
        }
    }

    public List<Vocabulary> GetVocabulariesForLevel(int level)
    {
        lock (_lock)
        {
            if (_levelVocabMap.TryGetValue(level, out var levelVocabs) && levelVocabs.Count > 0)
            {
                return CloneList(levelVocabs, level);
            }
        }

        // Try Database query if in-memory cache missed
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var dbList = context.Vocabularies.AsNoTracking().Where(v => v.LevelRequired == level).ToList();
            if (dbList.Count > 0)
            {
                lock (_lock)
                {
                    _levelVocabMap[level] = dbList;
                }
                return CloneList(dbList, level);
            }
        }
        catch { }

        // For advanced levels (25+), fetch dynamically from Jisho API if not yet cached
        if (level >= 25)
        {
            var jishoVocabs = FetchJishoVocabsForLevel(level);
            if (jishoVocabs.Count > 0)
            {
                lock (_lock)
                {
                    _levelVocabMap[level] = jishoVocabs;
                }

                // Persist to DB for future queries
                try
                {
                    using var scope = _scopeFactory.CreateScope();
                    var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                    var toAdd = jishoVocabs.Select(v => new Vocabulary
                    {
                        WordJp = v.WordJp,
                        Kana = v.Kana,
                        Romaji = v.Romaji,
                        Meaning = v.Meaning,
                        Type = v.Type,
                        LevelRequired = level
                    }).ToList();

                    context.Vocabularies.AddRange(toAdd);
                    context.SaveChanges();
                }
                catch { }

                return CloneList(jishoVocabs, level);
            }
        }

        return new List<Vocabulary>();
    }

    public List<Vocabulary> GetAllVocabularies()
    {
        lock (_lock)
        {
            if (_levelVocabMap.Count > 0)
            {
                var all = new List<Vocabulary>();
                var sortedLevels = _levelVocabMap.Keys.OrderBy(k => k);
                foreach (var level in sortedLevels)
                {
                    all.AddRange(CloneList(_levelVocabMap[level], level));
                }
                return all;
            }
        }

        // Fallback to database
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var dbAll = context.Vocabularies.AsNoTracking().ToList();
            if (dbAll.Count > 0)
            {
                lock (_lock)
                {
                    foreach (var v in dbAll)
                    {
                        if (!_levelVocabMap.TryGetValue(v.LevelRequired, out var list))
                        {
                            list = new List<Vocabulary>();
                            _levelVocabMap[v.LevelRequired] = list;
                        }
                        list.Add(v);
                    }
                }
                return dbAll;
            }
        }
        catch { }

        return new List<Vocabulary>();
    }

    public List<Vocabulary> SearchVocabularies(string? query)
    {
        if (string.IsNullOrWhiteSpace(query)) return new List<Vocabulary>();

        var lowerQuery = query.Trim().ToLowerInvariant();
        var results = new List<Vocabulary>();

        lock (_lock)
        {
            foreach (var (level, vocabs) in _levelVocabMap)
            {
                foreach (var v in vocabs)
                {
                    if ((v.WordJp != null && v.WordJp.ToLowerInvariant().Contains(lowerQuery)) ||
                        (v.Kana != null && v.Kana.ToLowerInvariant().Contains(lowerQuery)) ||
                        (v.Romaji != null && v.Romaji.ToLowerInvariant().Contains(lowerQuery)) ||
                        (v.Meaning != null && v.Meaning.ToLowerInvariant().Contains(lowerQuery)))
                    {
                        results.Add(new Vocabulary
                        {
                            Id = v.Id,
                            WordJp = v.WordJp ?? string.Empty,
                            Kana = v.Kana,
                            Romaji = v.Romaji ?? string.Empty,
                            Meaning = v.Meaning ?? string.Empty,
                            Type = v.Type,
                            LevelRequired = level
                        });

                        if (results.Count >= 100) return results;
                    }
                }
            }
        }

        // If in-memory results are sparse, search DB
        if (results.Count < 10)
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var dbMatches = context.Vocabularies
                    .AsNoTracking()
                    .Where(v => v.WordJp.Contains(lowerQuery) ||
                                (v.Kana != null && v.Kana.Contains(lowerQuery)) ||
                                v.Romaji.Contains(lowerQuery) ||
                                v.Meaning.Contains(lowerQuery))
                    .Take(100)
                    .ToList();

                foreach (var m in dbMatches)
                {
                    if (!results.Any(r => r.Id == m.Id || (r.WordJp == m.WordJp && r.LevelRequired == m.LevelRequired)))
                    {
                        results.Add(m);
                    }
                }
            }
            catch { }
        }

        return results;
    }

    private List<Vocabulary> FetchJishoVocabsForLevel(int level)
    {
        try
        {
            var offsetLevel = level - 25;
            var page = (offsetLevel / 2) + 1;
            var keyword = level < 50 ? "jlpt-n5" : (level < 75 ? "jlpt-n4" : "jlpt-n3");
            var url = $"https://jisho.org/api/v1/search/words?keyword={keyword}&page={page}";

            _logger.LogInformation("Calling Jisho API for level {Level} -> {Url}", level, url);

            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(6);
            var res = client.GetStringAsync(url).GetAwaiter().GetResult();

            using var doc = JsonDocument.Parse(res);
            if (doc.RootElement.TryGetProperty("data", out var dataArr) && dataArr.GetArrayLength() > 0)
            {
                var list = new List<Vocabulary>();
                var items = (offsetLevel % 2 == 0)
                    ? dataArr.EnumerateArray().Take(10)
                    : dataArr.EnumerateArray().Skip(10).Take(10);

                foreach (var item in items)
                {
                    string word = "";
                    string kana = "";
                    if (item.TryGetProperty("japanese", out var jpArr) && jpArr.GetArrayLength() > 0)
                    {
                        var firstJp = jpArr[0];
                        if (firstJp.TryGetProperty("word", out var w)) word = w.GetString() ?? "";
                        if (firstJp.TryGetProperty("reading", out var r)) kana = r.GetString() ?? "";
                    }
                    if (string.IsNullOrEmpty(word)) word = kana;
                    if (string.IsNullOrEmpty(kana)) kana = word;

                    string meaning = "";
                    if (item.TryGetProperty("senses", out var sensesArr) && sensesArr.GetArrayLength() > 0)
                    {
                        var firstSense = sensesArr[0];
                        if (firstSense.TryGetProperty("english_definitions", out var defs))
                        {
                            var defStrings = defs.EnumerateArray()
                                .Select(d => d.GetString() ?? "")
                                .Where(s => !string.IsNullOrEmpty(s));
                            meaning = string.Join(", ", defStrings);
                        }
                    }

                    list.Add(new Vocabulary
                    {
                        WordJp = word,
                        Kana = kana,
                        Romaji = ConvertKanaToRomaji(kana),
                        Meaning = meaning,
                        LevelRequired = level,
                        Type = WordType.KANJI
                    });
                }

                if (list.Count > 0) return list;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not fetch vocabularies from Jisho API for level {Level}", level);
        }

        return new List<Vocabulary>();
    }

    private static List<Vocabulary> CloneList(List<Vocabulary> list, int level)
    {
        var result = new List<Vocabulary>(list.Count);
        foreach (var baseVocab in list)
        {
            result.Add(new Vocabulary
            {
                Id = baseVocab.Id,
                WordJp = baseVocab.WordJp,
                Kana = baseVocab.Kana,
                Romaji = baseVocab.Romaji,
                Meaning = baseVocab.Meaning,
                Type = baseVocab.Type,
                LevelRequired = level
            });
        }
        return result;
    }

    public string ConvertKanaToRomaji(string kana)
    {
        if (string.IsNullOrWhiteSpace(kana)) return string.Empty;

        // 1. Try Kuroshiro microservice first
        try
        {
            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(2);
            var payload = JsonSerializer.Serialize(new { text = kana });
            using var content = new StringContent(payload, System.Text.Encoding.UTF8, "application/json");
            var response = client.PostAsync("http://localhost:8081/convert", content).GetAwaiter().GetResult();
            if (response.IsSuccessStatusCode)
            {
                var jsonStr = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                using var doc = JsonDocument.Parse(jsonStr);
                if (doc.RootElement.TryGetProperty("romaji", out var romajiProp))
                {
                    var romaji = romajiProp.GetString() ?? string.Empty;
                    romaji = romaji.Replace("ā", "aa")
                                   .Replace("ī", "ii")
                                   .Replace("ū", "uu")
                                   .Replace("ē", "ee")
                                   .Replace("ō", "ou");
                    if (!string.IsNullOrWhiteSpace(romaji) && romaji != kana)
                    {
                        return romaji.ToLowerInvariant();
                    }
                }
            }
        }
        catch { }

        // 2. Fallback to basic transliteration if microservice is offline
        return KanaToRomajiFallback(kana);
    }

    private static readonly Dictionary<string, string> KanaRomajiMap = new()
    {
        // Digraphs (Hiragana)
        ["きゃ"] = "kya", ["きゅ"] = "kyu", ["きょ"] = "kyo",
        ["しゃ"] = "sha", ["しゅ"] = "shu", ["しょ"] = "sho",
        ["ちゃ"] = "cha", ["ちゅ"] = "chu", ["ちょ"] = "cho",
        ["にゃ"] = "nya", ["にゅ"] = "nyu", ["にょ"] = "nyo",
        ["ひゃ"] = "hya", ["ひゅ"] = "hyu", ["ひょ"] = "hyo",
        ["みゃ"] = "mya", ["みゅ"] = "myu", ["みょ"] = "myo",
        ["りゃ"] = "rya", ["りゅ"] = "ryu", ["りょ"] = "ryo",
        ["ぎゃ"] = "gya", ["ぎゅ"] = "gyu", ["ぎょ"] = "gyo",
        ["じゃ"] = "ja",  ["じゅ"] = "ju",  ["じょ"] = "jo",
        ["ぢゃ"] = "ja",  ["ぢゅ"] = "ju",  ["ぢょ"] = "jo",
        ["びゃ"] = "bya", ["びゅ"] = "byu", ["びょ"] = "byo",
        ["ぴゃ"] = "pya", ["ぴゅ"] = "pyu", ["ぴょ"] = "pyo",

        // Digraphs (Katakana)
        ["キャ"] = "kya", ["キュ"] = "kyu", ["キョ"] = "kyo",
        ["シャ"] = "sha", ["シュ"] = "shu", ["ショ"] = "sho",
        ["チャ"] = "cha", ["チュ"] = "chu", ["チョ"] = "cho",
        ["ニャ"] = "nya", ["ニュ"] = "nyu", ["ニョ"] = "nyo",
        ["ヒャ"] = "hya", ["ヒュ"] = "hyu", ["ヒョ"] = "hyo",
        ["ミャ"] = "mya", ["ミュ"] = "myu", ["ミョ"] = "myo",
        ["リャ"] = "rya", ["リュ"] = "ryu", ["リョ"] = "ryo",
        ["ギャ"] = "gya", ["ギュ"] = "gyu", ["ギョ"] = "gyo",
        ["ジャ"] = "ja",  ["ジュ"] = "ju",  ["ジョ"] = "jo",
        ["ビャ"] = "bya", ["ビュ"] = "byu", ["ビョ"] = "byo",
        ["ピャ"] = "pya", ["ピュ"] = "pyu", ["ピョ"] = "pyo",
        ["ティ"] = "ti",  ["ディ"] = "di",  ["ファ"] = "fa",
        ["フィ"] = "fi",  ["フェ"] = "fe",  ["フォ"] = "fo",
        ["ウィ"] = "wi",  ["ウェ"] = "we",  ["ウォ"] = "wo",
        ["チェ"] = "che", ["シェ"] = "she", ["ジェ"] = "je",

        // Monographs (Hiragana)
        ["あ"] = "a",  ["い"] = "i",  ["う"] = "u",  ["え"] = "e",  ["お"] = "o",
        ["か"] = "ka", ["き"] = "ki", ["く"] = "ku", ["け"] = "ke", ["こ"] = "ko",
        ["さ"] = "sa", ["し"] = "shi",["す"] = "su", ["せ"] = "se", ["そ"] = "so",
        ["た"] = "ta", ["ち"] = "chi",["つ"] = "tsu",["て"] = "te", ["と"] = "to",
        ["な"] = "na", ["に"] = "ni", ["ぬ"] = "nu", ["ね"] = "ne", ["の"] = "no",
        ["は"] = "ha", ["ひ"] = "hi", ["ふ"] = "fu", ["へ"] = "he", ["ほ"] = "ho",
        ["ま"] = "ma", ["み"] = "mi", ["む"] = "mu", ["め"] = "me", ["も"] = "mo",
        ["や"] = "ya",                ["ゆ"] = "yu",                ["よ"] = "yo",
        ["ら"] = "ra", ["り"] = "ri", ["る"] = "ru", ["れ"] = "re", ["ろ"] = "ro",
        ["わ"] = "wa",                                              ["を"] = "wo",
        ["ん"] = "n",
        ["が"] = "ga", ["ぎ"] = "gi", ["ぐ"] = "gu", ["げ"] = "ge", ["ご"] = "go",
        ["ざ"] = "za", ["ジ"] = "ji", ["ず"] = "zu", ["ぜ"] = "ze", ["ぞ"] = "zo",
        ["だ"] = "da", ["ぢ"] = "ji", ["づ"] = "zu", ["で"] = "de", ["ど"] = "do",
        ["ば"] = "ba", ["び"] = "bi", ["ぶ"] = "bu", ["べ"] = "be", ["ぼ"] = "bo",
        ["ぱ"] = "pa", ["ぴ"] = "pi", ["ぷ"] = "pu", ["ぺ"] = "pe", ["ぽ"] = "po",

        // Monographs (Katakana)
        ["ア"] = "a",  ["イ"] = "i",  ["ウ"] = "u",  ["エ"] = "e",  ["オ"] = "o",
        ["カ"] = "ka", ["キ"] = "ki", ["ク"] = "ku", ["ケ"] = "ke", ["コ"] = "ko",
        ["サ"] = "sa", ["シ"] = "shi",["ス"] = "su", ["セ"] = "se", ["ソ"] = "so",
        ["タ"] = "ta", ["チ"] = "chi",["ツ"] = "tsu",["テ"] = "te", ["ト"] = "to",
        ["ナ"] = "na", ["ニ"] = "ni", ["ヌ"] = "nu", ["ネ"] = "ne", ["ノ"] = "no",
        ["ハ"] = "ha", ["ヒ"] = "hi", ["フ"] = "fu", ["ヘ"] = "he", ["ホ"] = "ho",
        ["マ"] = "ma", ["ミ"] = "mi", ["ム"] = "mu", ["メ"] = "me", ["モ"] = "mo",
        ["ヤ"] = "ya",                ["ユ"] = "yu",                ["ヨ"] = "yo",
        ["ラ"] = "ra", ["リ"] = "ri", ["ル"] = "ru", ["レ"] = "re", ["ロ"] = "ro",
        ["ワ"] = "wa",                                              ["ヲ"] = "wo",
        ["ン"] = "n",
        ["ガ"] = "ga", ["ギ"] = "gi", ["グ"] = "gu", ["ゲ"] = "ge", ["ゴ"] = "go",
        ["ザ"] = "za", ["ジ"] = "ji", ["ズ"] = "zu", ["ゼ"] = "ze", ["ゾ"] = "zo",
        ["ダ"] = "da", ["ヂ"] = "ji", ["ヅ"] = "zu", ["デ"] = "de", ["ド"] = "do",
        ["バ"] = "ba", ["ビ"] = "bi", ["ブ"] = "bu", ["ベ"] = "be", ["ボ"] = "bo",
        ["パ"] = "pa", ["ピ"] = "pi", ["プ"] = "pu", ["ペ"] = "pe", ["ぽ"] = "po",
        ["ヴ"] = "vu"
    };

    private static string KanaToRomajiFallback(string text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        var sb = new System.Text.StringBuilder();
        int i = 0;
        while (i < text.Length)
        {
            // Sokuon っ or ッ
            if ((text[i] == 'っ' || text[i] == 'ッ') && i + 1 < text.Length)
            {
                string nextPair = (i + 2 < text.Length) ? text.Substring(i + 1, 2) : "";
                if (!string.IsNullOrEmpty(nextPair) && KanaRomajiMap.TryGetValue(nextPair, out var nextR2))
                {
                    sb.Append(nextR2[0]);
                    sb.Append(nextR2);
                    i += 3;
                    continue;
                }
                string nextSingle = text.Substring(i + 1, 1);
                if (KanaRomajiMap.TryGetValue(nextSingle, out var nextR1))
                {
                    sb.Append(nextR1[0]);
                    sb.Append(nextR1);
                    i += 2;
                    continue;
                }
            }

            // Katakana long vowel mark ー
            if (text[i] == 'ー' && sb.Length > 0)
            {
                char last = sb[sb.Length - 1];
                if ("aiueo".Contains(last)) sb.Append(last);
                i++;
                continue;
            }

            // 2-char digraph
            if (i + 1 < text.Length)
            {
                string two = text.Substring(i, 2);
                if (KanaRomajiMap.TryGetValue(two, out var romaji2))
                {
                    sb.Append(romaji2);
                    i += 2;
                    continue;
                }
            }

            // 1-char
            string one = text.Substring(i, 1);
            if (KanaRomajiMap.TryGetValue(one, out var romaji1))
            {
                sb.Append(romaji1);
            }
            else
            {
                sb.Append(text[i]);
            }
            i++;
        }
        return sb.ToString().ToLowerInvariant();
    }
}
