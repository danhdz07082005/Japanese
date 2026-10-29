using JapaneseMasteryBackendDotNet.Models;
using Microsoft.AspNetCore.Http;

namespace JapaneseMasteryBackendDotNet.DTOs;

public class UploadItemRequest
{
    public string Name { get; set; } = string.Empty;
    public ShopItemType Type { get; set; }
    public int Price { get; set; }
    public long DesignerId { get; set; }
    public IFormFile File { get; set; } = null!;
}

