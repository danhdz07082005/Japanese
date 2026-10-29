using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Data;

public static class DatabaseInitializer
{
    public static async Task InitializeAsync(AppDbContext context, ILogger logger)
    {
        try
        {
            // 1. Ensure database schema is created (works transparently for SQLite and SQL Server)
            await context.Database.EnsureCreatedAsync();

            // 2. Specific migrations for SQL Server if running against legacy MSSQL instances
            if (context.Database.IsSqlServer())
            {
                try
                {
                    var sql = @"
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('users') AND name = 'pvp_ban_until')
    ALTER TABLE users ADD pvp_ban_until DATETIME2 NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('users') AND name = 'active_theme_id')
    ALTER TABLE users ADD active_theme_id BIGINT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('users') AND name = 'active_background_id')
    ALTER TABLE users ADD active_background_id BIGINT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('shop_items') AND name = 'cloudinary_public_id')
    ALTER TABLE shop_items ADD cloudinary_public_id VARCHAR(255) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('shop_items') AND name = 'secure_url')
    ALTER TABLE shop_items ADD secure_url VARCHAR(500) NULL;
";
                    await context.Database.ExecuteSqlRawAsync(sql);
                }
                catch (Exception sqlEx)
                {
                    logger.LogWarning("SQL Server schema check notice: {Message}", sqlEx.Message);
                }
            }

            // 3. Seed default admin account
            var adminUser = await context.Users.FirstOrDefaultAsync(u => u.Username == "admin");
            if (adminUser == null)
            {
                var admin = new User
                {
                    Username = "admin",
                    Password = BCrypt.Net.BCrypt.HashPassword("123"),
                    Role = Role.ADMIN,
                    Level = 99,
                    GCoin = 9999,
                    DisplayName = "System Admin"
                };
                context.Users.Add(admin);
                await context.SaveChangesAsync();
                adminUser = admin;
                logger.LogInformation("[DB] Default ADMIN account created: admin / 123");
            }

            // 4. Seed demo player account for instant multiplayer testing
            var testPlayer = await context.Users.FirstOrDefaultAsync(u => u.Username == "player2");
            if (testPlayer == null)
            {
                var p2 = new User
                {
                    Username = "player2",
                    Password = BCrypt.Net.BCrypt.HashPassword("123"),
                    Role = Role.PLAYER,
                    Level = 25, // Eligible for PvP
                    GCoin = 500,
                    DisplayName = "Kenji (Rival)"
                };
                context.Users.Add(p2);
                await context.SaveChangesAsync();
                logger.LogInformation("[DB] Demo player account created: player2 / 123 (Level 25)");
            }

            // 5. Seed default shop items
            if (!await context.ShopItems.AnyAsync())
            {
                var defaultItems = new List<ShopItem>
                {
                    new() { Name = "Sakura Pink Theme", Type = ShopItemType.THEME, Price = 500, IsApproved = true, DesignerId = adminUser.Id, SecureUrl = "https://images.unsplash.com/photo-1522383225653-ed111181a951" },
                    new() { Name = "Cyberpunk Neo-Tokyo", Type = ShopItemType.THEME, Price = 800, IsApproved = true, DesignerId = adminUser.Id, SecureUrl = "https://images.unsplash.com/photo-1509198397868-475647b2a1e5" },
                    new() { Name = "Mount Fuji Twilight", Type = ShopItemType.THEME, Price = 1000, IsApproved = true, DesignerId = adminUser.Id, SecureUrl = "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e" }
                };
                context.ShopItems.AddRange(defaultItems);
                await context.SaveChangesAsync();
                logger.LogInformation("[DB] Default Shop Items seeded.");
            }

            // 6. Ensure default vocabularies exist for Solo Learning
            if (!await context.Vocabularies.AnyAsync())
            {
                var defaultVocab = new List<Vocabulary>
                {
                    new() { WordJp = "ねこ", Kana = "ねこ", Romaji = "neko", Meaning = "Cat", LevelRequired = 1, Type = WordType.HIRAGANA },
                    new() { WordJp = "いぬ", Kana = "いぬ", Romaji = "inu", Meaning = "Dog", LevelRequired = 1, Type = WordType.HIRAGANA },
                    new() { WordJp = "さくら", Kana = "さくら", Romaji = "sakura", Meaning = "Cherry Blossom", LevelRequired = 1, Type = WordType.HIRAGANA },
                    new() { WordJp = "ほん", Kana = "ほん", Romaji = "hon", Meaning = "Book", LevelRequired = 1, Type = WordType.HIRAGANA },
                    new() { WordJp = "みず", Kana = "みず", Romaji = "mizu", Meaning = "Water", LevelRequired = 1, Type = WordType.HIRAGANA }
                };
                context.Vocabularies.AddRange(defaultVocab);
                await context.SaveChangesAsync();
                logger.LogInformation("[DB] Default Vocabularies seeded.");
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[DB] An error occurred while initializing the database.");
        }
    }
}
