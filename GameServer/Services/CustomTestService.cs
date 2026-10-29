using JapaneseMasteryBackendDotNet.Data;
using JapaneseMasteryBackendDotNet.DTOs;
using JapaneseMasteryBackendDotNet.Models;
using Microsoft.EntityFrameworkCore;

namespace JapaneseMasteryBackendDotNet.Services;

public class CustomTestService
{
    private readonly AppDbContext _context;

    public CustomTestService(AppDbContext context)
    {
        _context = context;
    }

    public async Task<CustomTestResponse> CreateCustomTestAsync(long senseiId, CustomTestRequest request)
    {
        var sensei = await _context.Users.FindAsync(senseiId);
        if (sensei == null)
        {
            throw new InvalidOperationException("User not found");
        }

        if (sensei.Role != Role.SENSEI)
        {
            throw new InvalidOperationException("Only SENSEI can create custom tests");
        }

        if (!request.MaxAttempts.HasValue || request.MaxAttempts.Value >= 10 || request.MaxAttempts.Value <= 0)
        {
            throw new InvalidOperationException("Max attempts must be between 1 and 9");
        }

        if (!request.RewardGcoin.HasValue || request.RewardGcoin.Value < 0)
        {
            throw new InvalidOperationException("Reward G-Coin must be positive");
        }

        var customTest = new CustomTest
        {
            Title = request.Title,
            TestCode = !string.IsNullOrEmpty(request.TestCode) ? request.TestCode : "TEST-" + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            MinLevel = request.MinLevel ?? 1,
            SenseiId = senseiId,
            RewardGcoin = request.RewardGcoin.Value,
            MaxAttempts = request.MaxAttempts.Value,
            IsApproved = true
        };

        _context.CustomTests.Add(customTest);
        await _context.SaveChangesAsync();

        if (request.Questions != null && request.Questions.Count > 0)
        {
            var questions = request.Questions.Select(q => new CustomTestQuestion
            {
                CustomTestId = customTest.Id,
                QuestionText = q.QuestionText,
                AnswerA = q.AnswerA,
                AnswerB = q.AnswerB,
                AnswerC = q.AnswerC,
                AnswerD = q.AnswerD,
                CorrectAnswer = q.CorrectAnswer
            }).ToList();

            _context.CustomTestQuestions.AddRange(questions);
            await _context.SaveChangesAsync();
        }

        return await MapToResponseAsync(customTest.Id);
    }

    public async Task<List<CustomTestResponse>> GetCustomTestsBySenseiAsync(long senseiId)
    {
        var sensei = await _context.Users.FindAsync(senseiId);
        if (sensei == null)
        {
            throw new InvalidOperationException("User not found");
        }

        if (sensei.Role != Role.SENSEI)
        {
            throw new InvalidOperationException("Only SENSEI can view their custom tests");
        }

        var tests = await _context.CustomTests
            .Include(t => t.Sensei)
            .Include(t => t.Questions)
            .Where(t => t.SenseiId == senseiId)
            .ToListAsync();

        return tests.Select(MapToResponse).ToList();
    }

    public async Task<CustomTestResponse> GetCustomTestByCodeAsync(string testCode)
    {
        var test = await _context.CustomTests
            .Include(t => t.Sensei)
            .Include(t => t.Questions)
            .FirstOrDefaultAsync(t => t.TestCode == testCode);

        if (test == null)
        {
            throw new InvalidOperationException("Test not found");
        }

        return MapToResponse(test);
    }

    public async Task<CustomTestResponse> GetCustomTestForPlayerAsync(long playerId, string testCode)
    {
        var test = await _context.CustomTests
            .Include(t => t.Sensei)
            .Include(t => t.Questions)
            .FirstOrDefaultAsync(t => t.TestCode == testCode);

        if (test == null)
        {
            throw new InvalidOperationException("Test not found");
        }

        if (!test.IsApproved)
        {
            throw new InvalidOperationException("Bài test này đang chờ kiểm duyệt và chưa được phép làm.");
        }

        var attempts = await _context.CustomTestAttempts
            .CountAsync(a => a.PlayerId == playerId && a.TestId == test.Id);

        if (attempts >= test.MaxAttempts)
        {
            throw new InvalidOperationException($"Bạn đã vượt quá số lần làm bài test này ({test.MaxAttempts} lần).");
        }

        return MapToResponse(test);
    }

    public async Task<User> SubmitCustomTestAsync(long playerId, string testCode, int score, bool passed)
    {
        var player = await _context.Users
            .Include(u => u.UserLearnedWords)
            .FirstOrDefaultAsync(u => u.Id == playerId);

        if (player == null)
        {
            throw new InvalidOperationException("User not found");
        }

        var test = await _context.CustomTests.FirstOrDefaultAsync(t => t.TestCode == testCode);
        if (test == null)
        {
            throw new InvalidOperationException("Test not found");
        }

        var attempts = await _context.CustomTestAttempts
            .CountAsync(a => a.PlayerId == playerId && a.TestId == test.Id);

        if (attempts >= test.MaxAttempts)
        {
            throw new InvalidOperationException("Bạn đã vượt quá số lần làm bài test này.");
        }

        var attempt = new CustomTestAttempt
        {
            PlayerId = playerId,
            TestId = test.Id,
            Score = score,
            Passed = passed,
            AttemptTime = DateTime.UtcNow
        };

        _context.CustomTestAttempts.Add(attempt);

        if (passed && test.RewardGcoin > 0)
        {
            player.GCoin += test.RewardGcoin;
        }

        await _context.SaveChangesAsync();
        return player;
    }

    public async Task<CustomTestResponse> UpdateCustomTestAsync(long senseiId, long testId, CustomTestRequest request)
    {
        var test = await _context.CustomTests
            .Include(t => t.Questions)
            .Include(t => t.Sensei)
            .FirstOrDefaultAsync(t => t.Id == testId);

        if (test == null)
        {
            throw new InvalidOperationException("Test not found");
        }

        if (test.SenseiId != senseiId)
        {
            throw new InvalidOperationException("You do not own this test");
        }

        if (request.MaxAttempts.HasValue)
        {
            if (request.MaxAttempts.Value >= 10 || request.MaxAttempts.Value <= 0)
            {
                throw new InvalidOperationException("Max attempts must be between 1 and 9");
            }
            test.MaxAttempts = request.MaxAttempts.Value;
        }

        if (request.RewardGcoin.HasValue)
        {
            if (request.RewardGcoin.Value < 0)
            {
                throw new InvalidOperationException("Reward G-Coin must be positive");
            }
            test.RewardGcoin = request.RewardGcoin.Value;
        }

        if (!string.IsNullOrEmpty(request.Title))
        {
            test.Title = request.Title;
        }

        if (!string.IsNullOrEmpty(request.TestCode))
        {
            test.TestCode = request.TestCode;
        }

        if (request.MinLevel.HasValue)
        {
            test.MinLevel = request.MinLevel.Value;
        }

        if (request.Questions != null)
        {
            _context.CustomTestQuestions.RemoveRange(test.Questions);

            var newQuestions = request.Questions.Select(q => new CustomTestQuestion
            {
                CustomTestId = test.Id,
                QuestionText = q.QuestionText,
                AnswerA = q.AnswerA,
                AnswerB = q.AnswerB,
                AnswerC = q.AnswerC,
                AnswerD = q.AnswerD,
                CorrectAnswer = q.CorrectAnswer
            }).ToList();

            _context.CustomTestQuestions.AddRange(newQuestions);
        }

        await _context.SaveChangesAsync();
        return await MapToResponseAsync(test.Id);
    }

    public async Task DeleteCustomTestAsync(long senseiId, long testId)
    {
        var test = await _context.CustomTests
            .Include(t => t.Questions)
            .FirstOrDefaultAsync(t => t.Id == testId);

        if (test == null)
        {
            throw new InvalidOperationException("Test not found");
        }

        if (test.SenseiId != senseiId)
        {
            throw new InvalidOperationException("You do not own this test");
        }

        var attempts = _context.CustomTestAttempts.Where(a => a.TestId == testId);
        _context.CustomTestAttempts.RemoveRange(attempts);

        _context.CustomTestQuestions.RemoveRange(test.Questions);
        _context.CustomTests.Remove(test);

        await _context.SaveChangesAsync();
    }

    public async Task<List<CustomTestAttemptDTO>> GetTestAttemptsAsync(long senseiId, long testId)
    {
        var test = await _context.CustomTests.FindAsync(testId);
        if (test == null)
        {
            throw new InvalidOperationException("Test not found");
        }

        if (test.SenseiId != senseiId)
        {
            throw new InvalidOperationException("You do not own this test");
        }

        var attempts = await _context.CustomTestAttempts
            .Include(a => a.Player)
            .Where(a => a.TestId == testId)
            .OrderByDescending(a => a.AttemptTime)
            .ToListAsync();

        return attempts.Select(a => new CustomTestAttemptDTO
        {
            PlayerName = a.Player?.Username ?? "Unknown",
            Score = a.Score,
            Passed = a.Passed,
            AttemptTime = a.AttemptTime
        }).ToList();
    }

    private async Task<CustomTestResponse> MapToResponseAsync(long testId)
    {
        var test = await _context.CustomTests
            .Include(t => t.Sensei)
            .Include(t => t.Questions)
            .FirstAsync(t => t.Id == testId);

        return MapToResponse(test);
    }

    private static CustomTestResponse MapToResponse(CustomTest test)
    {
        return new CustomTestResponse
        {
            Id = test.Id,
            Title = test.Title,
            TestCode = test.TestCode,
            MinLevel = test.MinLevel,
            RewardGcoin = test.RewardGcoin,
            MaxAttempts = test.MaxAttempts,
            IsApproved = test.IsApproved,
            SenseiId = test.SenseiId,
            SenseiUsername = test.Sensei?.Username ?? string.Empty,
            Questions = test.Questions.Select(q => new CustomTestQuestionDTO
            {
                Id = q.Id,
                QuestionText = q.QuestionText,
                AnswerA = q.AnswerA,
                AnswerB = q.AnswerB,
                AnswerC = q.AnswerC,
                AnswerD = q.AnswerD,
                CorrectAnswer = q.CorrectAnswer
            }).ToList()
        };
    }
}

