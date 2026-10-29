using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace JapaneseMasteryBackendDotNet.Controllers;

[Authorize(Roles = "ADMIN")]
[ApiController]
[Route("api/admin/vocabularies")]
public class AdminVocabController : ControllerBase
{
    private readonly VocabularyService _vocabularyService;
    private readonly JMdictService _jmdictService;

    public AdminVocabController(VocabularyService vocabularyService, JMdictService jmdictService)
    {
        _vocabularyService = vocabularyService;
        _jmdictService = jmdictService;
    }

    [HttpGet]
    public IActionResult GetAllVocabularies([FromQuery] int? level, [FromQuery] string? q)
    {
        if (!string.IsNullOrWhiteSpace(q))
        {
            var results = _jmdictService.SearchVocabularies(q);
            return Ok(results);
        }

        if (level.HasValue)
        {
            return Ok(_jmdictService.GetVocabulariesForLevel(level.Value));
        }

        return Ok(_jmdictService.GetAllVocabularies());
    }

    [HttpPut("{id}/level")]
    public async Task<IActionResult> UpdateVocabularyLevel([FromRoute] long id, [FromQuery] int level)
    {
        try
        {
            var vocab = await _vocabularyService.UpdateVocabularyLevelAsync(id, level);
            return Ok(vocab);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}

