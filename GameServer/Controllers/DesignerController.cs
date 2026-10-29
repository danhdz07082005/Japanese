using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Models;
using JapaneseMasteryBackendDotNet.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace JapaneseMasteryBackendDotNet.Controllers;

[Authorize(Roles = "DESIGNER,ADMIN")]
[ApiController]
[Route("api/designer/{designerId}/items")]
public class DesignerController : ControllerBase
{
    private readonly ShopService _shopService;
    private readonly AppDbContext _context;

    public DesignerController(ShopService shopService, AppDbContext context)
    {
        _shopService = shopService;
        _context = context;
    }

    [HttpGet]
    public async Task<IActionResult> GetDesignerItems([FromRoute] long designerId)
    {
        var items = await _shopService.GetDesignerItemsAsync(designerId);
        return Ok(items);
    }

    [HttpPost]
    public async Task<IActionResult> CreateShopItem([FromRoute] long designerId, [FromBody] ShopItemRequest request)
    {
        var designer = await _context.Users.FindAsync(designerId);
        if (designer == null || designer.Role != Role.DESIGNER)
        {
            return BadRequest("User is not a valid designer.");
        }

        var item = new ShopItem
        {
            DesignerId = designerId,
            Name = request.Name,
            Price = request.Price,
            Type = request.Type,
            IsApproved = true
        };

        _context.ShopItems.Add(item);
        designer.PurchasedItems.Add(item);
        await _context.SaveChangesAsync();

        return Ok("Item created successfully and is now active in the Shop.");
    }
}
