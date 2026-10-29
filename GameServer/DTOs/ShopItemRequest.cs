using JapaneseMasteryBackendDotNet.Models;

namespace JapaneseMasteryBackendDotNet.DTOs;

public class ShopItemRequest
{
    public string Name { get; set; } = string.Empty;
    public int Price { get; set; }
    public ShopItemType Type { get; set; }
}

