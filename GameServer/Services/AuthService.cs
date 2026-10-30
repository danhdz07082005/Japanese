using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Logging;
using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Services;

public class AuthService
{
    private readonly AppDbContext _context;
    private readonly JwtService _jwtService;
    private readonly PyTunnelLogSink _logSink;

    public AuthService(AppDbContext context, JwtService jwtService, PyTunnelLogSink logSink)
    {
        _context = context;
        _jwtService = jwtService;
        _logSink = logSink;
    }

    public async Task<AuthResponse> RegisterAsync(AuthRequest request)
    {
        var exists = await _context.Users.AnyAsync(u => u.Username == request.Username);
        if (exists)
        {
            throw new InvalidOperationException("Username already exists");
        }

        var user = new User
        {
            Username = request.Username,
            Password = BCrypt.Net.BCrypt.HashPassword(request.Password),
            Role = Role.PLAYER,
            Level = 1,
            GCoin = 0
        };

        _context.Users.Add(user);
        await _context.SaveChangesAsync();

        var token = _jwtService.GenerateToken(user);
        user.AccessToken = token;
        await _context.SaveChangesAsync();

        _logSink.Enqueue("STORE", "AUTH", $"✨ [ĐĂNG KÝ] Chào mừng tân thủ '{user.Username}' gia nhập game! (Cấp {user.Level}, {user.GCoin} GCoin)");

        return new AuthResponse
        {
            Id = user.Id,
            Token = token,
            Username = user.Username,
            Role = user.Role,
            Level = user.Level,
            GCoin = user.GCoin
        };
    }

    public async Task<AuthResponse> LoginAsync(AuthRequest request)
    {
        var user = await _context.Users
            .Include(u => u.PurchasedItems)
            .Include(u => u.ActiveTheme)
            .FirstOrDefaultAsync(u => u.Username == request.Username);
        if (user == null || !BCrypt.Net.BCrypt.Verify(request.Password, user.Password))
        {
            throw new InvalidOperationException("Invalid username or password");
        }

        if (!string.IsNullOrEmpty(user.AccessToken) && _jwtService.ValidateToken(user.AccessToken))
        {
            throw new InvalidOperationException("Account is already logged in on another device!");
        }

        // Validate active theme: user must own it or be its creator (designer/admin)
        if (user.ActiveThemeId != null)
        {
            bool isDesignerOwner = (user.Role == Role.DESIGNER || user.Role == Role.ADMIN) && user.ActiveTheme?.DesignerId == user.Id;
            if (!user.PurchasedItems.Any(i => i.Id == user.ActiveThemeId) && !isDesignerOwner)
            {
                user.ActiveThemeId = null;
                user.ActiveTheme = null;
            }
        }

        var token = _jwtService.GenerateToken(user);
        user.AccessToken = token;
        await _context.SaveChangesAsync();

        _logSink.Enqueue("STORE", "AUTH", $"👤 [ĐĂNG NHẬP] Người chơi '{user.Username}' vừa online (Cấp {user.Level}, {user.GCoin} GCoin, Quyền: {user.Role})");

        return new AuthResponse
        {
            Id = user.Id,
            Token = token,
            Username = user.Username,
            Role = user.Role,
            Level = user.Level,
            GCoin = user.GCoin,
            ActiveThemeId = user.ActiveThemeId,
            ActiveThemeUrl = user.ActiveTheme?.SecureUrl,
            PurchasedItemIds = user.PurchasedItems.Select(i => i.Id).ToList()
        };
    }

    public async Task LogoutAsync(long id)
    {
        var user = await _context.Users.FindAsync(id);
        if (user != null)
        {
            _logSink.Enqueue("STORE", "AUTH", $"👋 [ĐĂNG XUẤT] Người chơi '{user.Username}' vừa đăng xuất.");
            user.AccessToken = null;
            await _context.SaveChangesAsync();
        }
    }
}
