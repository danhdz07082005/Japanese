using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Services;

public class UserService
{
    private readonly AppDbContext _context;

    public UserService(AppDbContext context)
    {
        _context = context;
    }

    public async Task<List<User>> GetAllUsersAsync()
    {
        return await _context.Users
            .Include(u => u.UserLearnedWords)
            .ToListAsync();
    }

    public async Task<User> GetUserByIdAsync(long id)
    {
        var user = await _context.Users
            .Include(u => u.UserLearnedWords)
            .FirstOrDefaultAsync(u => u.Id == id);

        if (user == null)
        {
            throw new InvalidOperationException("User not found");
        }

        return user;
    }

    public async Task DeleteUserAsync(long id)
    {
        var user = await GetUserByIdAsync(id);
        if (user.Role == Role.ADMIN)
        {
            throw new InvalidOperationException("Cannot delete ADMIN account");
        }

        _context.Users.Remove(user);
        await _context.SaveChangesAsync();
    }

    public async Task<User> ChangeUserRoleAsync(long id, Role newRole)
    {
        var user = await GetUserByIdAsync(id);
        if (user.Role == Role.ADMIN)
        {
            throw new InvalidOperationException("Cannot change role of ADMIN account");
        }

        user.Role = newRole;
        await _context.SaveChangesAsync();
        return user;
    }

    public async Task<User> ChangeUserLevelAsync(long id, int newLevel)
    {
        var user = await GetUserByIdAsync(id);
        user.Level = newLevel;
        await _context.SaveChangesAsync();
        return user;
    }
}

