using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Mvc;

namespace JapaneseMasteryBackendDotNet.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AuthService _authService;

    public AuthController(AuthService authService)
    {
        _authService = authService;
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] AuthRequest request)
    {
        try
        {
            var response = await _authService.RegisterAsync(request);
            return Ok(response);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] AuthRequest request)
    {
        try
        {
            var response = await _authService.LoginAsync(request);
            return Ok(response);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPost("logout/{id}")]
    public async Task<IActionResult> Logout([FromRoute] long id)
    {
        await _authService.LogoutAsync(id);
        return Ok();
    }
}

