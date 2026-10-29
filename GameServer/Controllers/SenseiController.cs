using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace JapaneseMasteryBackendDotNet.Controllers;

[Authorize(Roles = "SENSEI,ADMIN")]
[ApiController]
[Route("api/sensei")]
public class SenseiController : ControllerBase
{
    private readonly CustomTestService _customTestService;
    private readonly AppDbContext _context;

    public SenseiController(CustomTestService customTestService, AppDbContext context)
    {
        _customTestService = customTestService;
        _context = context;
    }

    private async Task<bool> ValidateTokenAsync(long senseiId)
    {
        var authHeader = Request.Headers.Authorization.FirstOrDefault();
        if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return true; // Optional check
        }

        var sensei = await _context.Users.FindAsync(senseiId);
        if (sensei == null) return false;

        var token = authHeader.Substring(7).Trim();
        return token == sensei.AccessToken;
    }

    [HttpPost("{senseiId}/custom-tests")]
    public async Task<IActionResult> CreateCustomTest(
        [FromRoute] long senseiId,
        [FromBody] CustomTestRequest request)
    {
        if (!await ValidateTokenAsync(senseiId))
        {
            return Unauthorized();
        }

        try
        {
            var response = await _customTestService.CreateCustomTestAsync(senseiId, request);
            return Ok(response);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("{senseiId}/custom-tests")]
    public async Task<IActionResult> GetCustomTests(
        [FromRoute] long senseiId)
    {
        if (!await ValidateTokenAsync(senseiId))
        {
            return Unauthorized();
        }

        try
        {
            var responses = await _customTestService.GetCustomTestsBySenseiAsync(senseiId);
            return Ok(responses);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpGet("{senseiId}/tests/{testId}/attempts")]
    public async Task<IActionResult> GetTestAttempts(
        [FromRoute] long senseiId,
        [FromRoute] long testId)
    {
        if (!await ValidateTokenAsync(senseiId))
        {
            return Unauthorized();
        }

        try
        {
            var attempts = await _customTestService.GetTestAttemptsAsync(senseiId, testId);
            return Ok(attempts);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPut("{senseiId}/custom-tests/{testId}")]
    public async Task<IActionResult> UpdateCustomTest(
        [FromRoute] long senseiId,
        [FromRoute] long testId,
        [FromBody] CustomTestRequest request)
    {
        if (!await ValidateTokenAsync(senseiId))
        {
            return Unauthorized();
        }

        try
        {
            var response = await _customTestService.UpdateCustomTestAsync(senseiId, testId, request);
            return Ok(response);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpDelete("{senseiId}/custom-tests/{testId}")]
    public async Task<IActionResult> DeleteCustomTest(
        [FromRoute] long senseiId,
        [FromRoute] long testId)
    {
        if (!await ValidateTokenAsync(senseiId))
        {
            return Unauthorized();
        }

        try
        {
            await _customTestService.DeleteCustomTestAsync(senseiId, testId);
            return Ok();
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}

