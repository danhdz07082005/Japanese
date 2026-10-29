using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Models;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace JapaneseMasteryBackendDotNet.Controllers;

[ApiController]
[Route("api/shop")]
public class ShopController : ControllerBase
{
    private readonly ShopService _shopService;

    public ShopController(ShopService shopService)
    {
        _shopService = shopService;
    }

    [Authorize(Roles = "DESIGNER,ADMIN")]
    [HttpPost("items")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> UploadItem([FromForm] UploadItemRequest request)
    {
        try
        {
            var item = await _shopService.UploadItemToShopAsync(
                request.Name,
                request.Type,
                request.Price,
                request.DesignerId,
                request.File);
            return Ok(item);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = ex.Message });
        }
    }

    [HttpGet("items")]
    public async Task<IActionResult> GetItems()
    {
        var items = await _shopService.GetAllItemsAsync();
        return Ok(items);
    }

    [HttpGet("items/designer/{designerId}")]
    public async Task<IActionResult> GetDesignerItems([FromRoute] long designerId)
    {
        var items = await _shopService.GetDesignerItemsAsync(designerId);
        return Ok(items);
    }

    [HttpGet("items/{id}/use")]
    public async Task<IActionResult> UseItem([FromRoute] long id)
    {
        try
        {
            var optimizedUrl = await _shopService.GetOptimizedItemUrlForPlayerAsync(id);
            return Ok(optimizedUrl);
        }
        catch (Exception ex)
        {
            return BadRequest(ex.Message);
        }
    }

    [HttpPost("items/{itemId}/buy")]
    public async Task<IActionResult> BuyItem([FromRoute] long itemId, [FromQuery] long userId)
    {
        try
        {
            var updatedUser = await _shopService.BuyItemAsync(userId, itemId);
            return Ok(updatedUser);
        }
        catch (Exception ex)
        {
            return BadRequest(ex.Message);
        }
    }

    [HttpPost("items/{itemId}/apply")]
    public async Task<IActionResult> ApplyItem([FromRoute] long itemId, [FromQuery] long userId)
    {
        try
        {
            var updatedUser = await _shopService.ApplyItemAsync(userId, itemId);
            return Ok(updatedUser);
        }
        catch (Exception ex)
        {
            return BadRequest(ex.Message);
        }
    }

    [HttpPost("items/unequip")]
    public async Task<IActionResult> UnequipTheme([FromQuery] long userId)
    {
        try
        {
            var updatedUser = await _shopService.UnequipThemeAsync(userId);
            return Ok(updatedUser);
        }
        catch (Exception ex)
        {
            return BadRequest(ex.Message);
        }
    }

    [HttpGet("user/{userId}")]
    public async Task<IActionResult> GetUserShopData([FromRoute] long userId)
    {
        var data = await _shopService.GetUserShopDataAsync(userId);
        if (data == null) return NotFound("User not found");
        return Ok(data);
    }
}

