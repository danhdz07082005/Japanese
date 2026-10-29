using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Mvc;

namespace JapaneseMasteryBackendDotNet.Controllers;

[ApiController]
[Route("api/pvp")]
public class PvPController : ControllerBase
{
    private readonly PvPService _pvpService;

    public PvPController(PvPService pvpService)
    {
        _pvpService = pvpService;
    }

    [HttpPost("queue/join/{userId}")]
    public async Task<IActionResult> JoinQueue([FromRoute] long userId)
    {
        var result = await _pvpService.JoinQueueAsync(userId);
        if ("INELIGIBLE".Equals(result, StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest("Player is not eligible.");
        }
        if ("BANNED".Equals(result, StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest("BANNED");
        }
        return Ok(result);
    }

    [HttpPost("queue/leave/{userId}")]
    public IActionResult LeaveQueue([FromRoute] long userId)
    {
        _pvpService.LeaveQueue(userId);
        return Ok("LEFT_QUEUE");
    }

    [HttpPost("match/quit/{userId}")]
    public async Task<IActionResult> QuitMatch([FromRoute] long userId)
    {
        var result = await _pvpService.QuitMatchAsync(userId);
        return Ok(result);
    }

    [HttpGet("status/{userId}")]
    public async Task<IActionResult> GetStatus([FromRoute] long userId)
    {
        var status = await _pvpService.GetStatusAsync(userId);
        return Ok(status);
    }

    [HttpPost("match/progress/{userId}")]
    public IActionResult UpdateProgress([FromRoute] long userId, [FromQuery] int progress)
    {
        var result = _pvpService.UpdateProgress(userId, progress);
        return Ok(result);
    }

    [HttpPost("match/finish/{userId}")]
    public async Task<IActionResult> FinishMatch([FromRoute] long userId, [FromQuery] long timeMs)
    {
        var result = await _pvpService.FinishMatchAsync(userId, timeMs);
        return Ok(result);
    }

    [HttpPost("match/ack/{userId}")]
    public IActionResult AcknowledgeFinish([FromRoute] long userId)
    {
        _pvpService.AcknowledgeFinish(userId);
        return Ok("ACKNOWLEDGED");
    }

    // ============ LOBBY ENDPOINTS ============

    [HttpPost("lobby/create/{userId}")]
    public async Task<IActionResult> CreateLobby([FromRoute] long userId)
    {
        var result = await _pvpService.CreateLobbyAsync(userId);
        if (result.ContainsKey("error"))
        {
            return BadRequest(result);
        }
        return Ok(result);
    }

    [HttpPost("lobby/join/{code}/{userId}")]
    public async Task<IActionResult> JoinLobby([FromRoute] string code, [FromRoute] long userId)
    {
        var result = await _pvpService.JoinLobbyAsync(code.ToUpperInvariant(), userId);
        if (result.ContainsKey("error"))
        {
            return BadRequest(result);
        }
        return Ok(result);
    }

    [HttpPost("lobby/cancel/{code}/{userId}")]
    public IActionResult CancelLobby([FromRoute] string code, [FromRoute] long userId)
    {
        _pvpService.CancelLobby(code.ToUpperInvariant(), userId);
        return Ok("LOBBY_CANCELLED");
    }
}

