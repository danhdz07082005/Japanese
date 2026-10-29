using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<UserLearnedWord> UserLearnedWords => Set<UserLearnedWord>();
    public DbSet<Vocabulary> Vocabularies => Set<Vocabulary>();
    public DbSet<ShopItem> ShopItems => Set<ShopItem>();
    public DbSet<CustomTest> CustomTests => Set<CustomTest>();
    public DbSet<CustomTestQuestion> CustomTestQuestions => Set<CustomTestQuestion>();
    public DbSet<CustomTestAttempt> CustomTestAttempts => Set<CustomTestAttempt>();
    public DbSet<LearningProgress> LearningProgresses => Set<LearningProgress>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // User
        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("users");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.Username).HasColumnName("username").IsRequired();
            entity.Property(e => e.Password).HasColumnName("password").IsRequired();
            entity.Property(e => e.Role).HasColumnName("role").HasConversion<string>();
            entity.Property(e => e.Level).HasColumnName("level");
            entity.Property(e => e.GCoin).HasColumnName("g_coin");
            entity.Property(e => e.DisplayName).HasColumnName("display_name");
            entity.Property(e => e.AccessToken).HasColumnName("access_token");
            entity.Property(e => e.PvpBanUntil).HasColumnName("pvp_ban_until");
            entity.Property(e => e.ActiveThemeId).HasColumnName("active_theme_id");
            entity.Property(e => e.ActiveBackgroundId).HasColumnName("active_background_id");

            entity.HasOne(e => e.ActiveTheme)
                  .WithMany()
                  .HasForeignKey(e => e.ActiveThemeId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(e => e.ActiveBackground)
                  .WithMany()
                  .HasForeignKey(e => e.ActiveBackgroundId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasMany(e => e.PurchasedItems)
                  .WithMany()
                  .UsingEntity<Dictionary<string, object>>(
                      "user_purchased_items",
                      j => j.HasOne<ShopItem>().WithMany().HasForeignKey("item_id"),
                      j => j.HasOne<User>().WithMany().HasForeignKey("user_id"),
                      j =>
                      {
                          j.ToTable("user_purchased_items");
                          j.HasKey("user_id", "item_id");
                      });

            entity.HasMany(e => e.UserLearnedWords)
                  .WithOne(ul => ul.User)
                  .HasForeignKey(ul => ul.UserId);
        });

        // UserLearnedWord
        modelBuilder.Entity<UserLearnedWord>(entity =>
        {
            entity.ToTable("user_learned_words");
            entity.HasKey(e => new { e.UserId, e.WordJp });
            entity.Property(e => e.UserId).HasColumnName("user_id");
            entity.Property(e => e.WordJp).HasColumnName("word_jp");
        });

        // Vocabulary
        modelBuilder.Entity<Vocabulary>(entity =>
        {
            entity.ToTable("vocabularies");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.WordJp).HasColumnName("word_jp");
            entity.Property(e => e.Kana).HasColumnName("kana");
            entity.Property(e => e.Romaji).HasColumnName("romaji");
            entity.Property(e => e.Meaning).HasColumnName("meaning");
            entity.Property(e => e.LevelRequired).HasColumnName("level_required");
            entity.Property(e => e.Type).HasColumnName("type").HasConversion<string>();
            entity.Ignore(e => e.Level);
        });

        // ShopItem
        modelBuilder.Entity<ShopItem>(entity =>
        {
            entity.ToTable("shop_items");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.Name).HasColumnName("name");
            entity.Property(e => e.Type).HasColumnName("type").HasConversion<string>();
            entity.Property(e => e.Price).HasColumnName("price");
            entity.Property(e => e.CloudinaryPublicId).HasColumnName("cloudinary_public_id");
            entity.Property(e => e.SecureUrl).HasColumnName("secure_url");
            entity.Property(e => e.DesignerId).HasColumnName("designer_id");
            entity.Property(e => e.IsApproved).HasColumnName("is_approved");

            entity.HasOne(e => e.Designer)
                  .WithMany()
                  .HasForeignKey(e => e.DesignerId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        // CustomTest
        modelBuilder.Entity<CustomTest>(entity =>
        {
            entity.ToTable("custom_tests");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.Title).HasColumnName("title");
            entity.Property(e => e.SenseiId).HasColumnName("sensei_id");
            entity.Property(e => e.TestCode).HasColumnName("test_code");
            entity.Property(e => e.MinLevel).HasColumnName("min_level");
            entity.Property(e => e.RewardGcoin).HasColumnName("reward_gcoin");
            entity.Property(e => e.MaxAttempts).HasColumnName("max_attempts");
            entity.Property(e => e.IsApproved).HasColumnName("is_approved");

            entity.HasOne(e => e.Sensei)
                  .WithMany()
                  .HasForeignKey(e => e.SenseiId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasMany(e => e.Questions)
                  .WithOne(q => q.CustomTest)
                  .HasForeignKey(q => q.CustomTestId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // CustomTestQuestion
        modelBuilder.Entity<CustomTestQuestion>(entity =>
        {
            entity.ToTable("custom_test_questions");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.CustomTestId).HasColumnName("custom_test_id");
            entity.Property(e => e.QuestionText).HasColumnName("question_text");
            entity.Property(e => e.AnswerA).HasColumnName("answer_a");
            entity.Property(e => e.AnswerB).HasColumnName("answer_b");
            entity.Property(e => e.AnswerC).HasColumnName("answer_c");
            entity.Property(e => e.AnswerD).HasColumnName("answer_d");
            entity.Property(e => e.CorrectAnswer).HasColumnName("correct_answer");
        });

        // CustomTestAttempt
        modelBuilder.Entity<CustomTestAttempt>(entity =>
        {
            entity.ToTable("custom_test_attempts");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.PlayerId).HasColumnName("player_id");
            entity.Property(e => e.TestId).HasColumnName("test_id");
            entity.Property(e => e.Score).HasColumnName("score");
            entity.Property(e => e.Passed).HasColumnName("passed");
            entity.Property(e => e.AttemptTime).HasColumnName("attempt_time");

            entity.HasOne(e => e.Player)
                  .WithMany()
                  .HasForeignKey(e => e.PlayerId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(e => e.Test)
                  .WithMany()
                  .HasForeignKey(e => e.TestId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // LearningProgress
        modelBuilder.Entity<LearningProgress>(entity =>
        {
            entity.ToTable("learning_progress");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.UserId).HasColumnName("user_id");
            entity.Property(e => e.WordJp).HasColumnName("word_jp");
            entity.Property(e => e.VocabularyId).HasColumnName("vocabulary_id");
            entity.Property(e => e.IsMemorized).HasColumnName("is_memorized");
            entity.Property(e => e.HesitationCount).HasColumnName("hesitation_count");
            entity.Property(e => e.LastReviewTime).HasColumnName("last_review_time");
            entity.Property(e => e.IsWritingPassed).HasColumnName("is_writing_passed");
        });
    }
}

