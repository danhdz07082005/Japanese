using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Models;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Controllers;

[ApiController]
[Route("api/player")]
public class PlayerController : ControllerBase
{
    private readonly AppDbContext _context;
    private readonly CustomTestService _customTestService;
    private readonly VocabularyService _vocabularyService;

    public PlayerController(
        AppDbContext context,
        CustomTestService customTestService,
        VocabularyService vocabularyService)
    {
        _context = context;
        _customTestService = customTestService;
        _vocabularyService = vocabularyService;
    }

    [HttpGet("{id}/heartbeat")]
    public async Task<IActionResult> Heartbeat([FromRoute] long id)
    {
        var authHeader = Request.Headers.Authorization.FirstOrDefault();
        var user = await _context.Users.FindAsync(id);
        if (user == null) return NotFound("User not found");

        if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            var token = authHeader.Substring(7).Trim();
            if (token != user.AccessToken)
            {
                return Unauthorized();
            }
        }

        return Ok();
    }

    [HttpPut("{id}/progress")]
    public async Task<IActionResult> UpdateProgress(
        [FromRoute] long id,
        [FromQuery] int level,
        [FromBody] List<string>? newLearnedWords = null)
    {
        var authHeader = Request.Headers.Authorization.FirstOrDefault();
        var user = await _context.Users
            .Include(u => u.UserLearnedWords)
            .FirstOrDefaultAsync(u => u.Id == id);

        if (user == null) return NotFound("User not found");

        if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            var token = authHeader.Substring(7).Trim();
            if (token != user.AccessToken)
            {
                return Unauthorized();
            }
        }

        if (newLearnedWords != null && newLearnedWords.Count > 0)
        {
            var existingWords = user.UserLearnedWords.Select(w => w.WordJp).ToHashSet();
            foreach (var w in newLearnedWords)
            {
                if (!existingWords.Contains(w))
                {
                    user.UserLearnedWords.Add(new UserLearnedWord { UserId = user.Id, WordJp = w });
                    existingWords.Add(w);
                }
            }
        }

        if (level > user.Level)
        {
            user.Level = level;
        }

        await _context.SaveChangesAsync();
        return Ok(user);
    }

    [HttpGet("vocabularies")]
    public async Task<IActionResult> GetVocabulariesForLevel([FromQuery] int level, [FromQuery] long? userId = null)
    {
        HashSet<string>? learnedWords = null;
        if (userId.HasValue)
        {
            var user = await _context.Users
                .Include(u => u.UserLearnedWords)
                .FirstOrDefaultAsync(u => u.Id == userId.Value);

            if (user != null)
            {
                learnedWords = user.UserLearnedWords.Select(w => w.WordJp).ToHashSet();
            }
        }

        var vocabs = _vocabularyService.GetVocabulariesForLevel(level, learnedWords);
        return Ok(vocabs);
    }

    [HttpPut("{id}/coins")]
    public async Task<IActionResult> UpdateCoins(
        [FromRoute] long id,
        [FromQuery] int coins)
    {
        var authHeader = Request.Headers.Authorization.FirstOrDefault();
        var user = await _context.Users
            .Include(u => u.UserLearnedWords)
            .FirstOrDefaultAsync(u => u.Id == id);

        if (user == null) return NotFound("User not found");

        if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            var token = authHeader.Substring(7).Trim();
            if (token != user.AccessToken)
            {
                return Unauthorized();
            }
        }

        user.GCoin = coins;
        await _context.SaveChangesAsync();
        return Ok(user);
    }

    [HttpGet("{id}/custom-tests/{testCode}")]
    public async Task<IActionResult> GetCustomTest(
        [FromRoute] long id,
        [FromRoute] string testCode)
    {
        var authHeader = Request.Headers.Authorization.FirstOrDefault();
        try
        {
            var response = await _customTestService.GetCustomTestForPlayerAsync(id, testCode);
            return Ok(response);
        }
        catch (Exception ex)
        {
            return BadRequest(ex.Message);
        }
    }

    [HttpPost("{id}/custom-tests/{testCode}/submit")]
    public async Task<IActionResult> SubmitCustomTest(
        [FromRoute] long id,
        [FromRoute] string testCode,
        [FromBody] SubmitTestRequest body)
    {
        try
        {
            var updatedUser = await _customTestService.SubmitCustomTestAsync(id, testCode, body.Score, body.Passed);
            return Ok(updatedUser);
        }
        catch (Exception ex)
        {
            return BadRequest(ex.Message);
        }
    }
}

