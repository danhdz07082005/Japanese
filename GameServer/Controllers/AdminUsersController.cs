using JapaneseMasteryBackendDotNet.Models;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace JapaneseMasteryBackendDotNet.Controllers;

[Authorize(Roles = "ADMIN")]
[ApiController]
[Route("api/admin/users")]
public class AdminUsersController : ControllerBase
{
    private readonly UserService _userService;

    public AdminUsersController(UserService userService)
    {
        _userService = userService;
    }

    [HttpGet]
    public async Task<IActionResult> GetAllUsers()
    {
        var users = await _userService.GetAllUsersAsync();
        return Ok(users);
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteUser([FromRoute] long id)
    {
        try
        {
            await _userService.DeleteUserAsync(id);
            return Ok();
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPut("{id}/role")]
    public async Task<IActionResult> ChangeRole([FromRoute] long id, [FromQuery] Role role)
    {
        try
        {
            var user = await _userService.ChangeUserRoleAsync(id, role);
            return Ok(user);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }

    [HttpPut("{id}/level")]
    public async Task<IActionResult> ChangeLevel([FromRoute] long id, [FromQuery] int level)
    {
        try
        {
            var user = await _userService.ChangeUserLevelAsync(id, level);
            return Ok(user);
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}

