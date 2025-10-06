using Microsoft.Graph;
using Microsoft.Graph.Models;
using NSubstitute;
using Xunit;

namespace GraphEmailService.Tests;

public class EmailServiceTests
{
    private readonly GraphServiceClient _mockGraphServiceClient;
    private readonly EmailService _emailService;

    public EmailServiceTests()
    {
        _mockGraphServiceClient = Substitute.For<GraphServiceClient>();
        _emailService = new EmailService(_mockGraphServiceClient);
    }

    [Fact]
    public async Task SendEmailAsync_ValidParameters_SendsEmailSuccessfully()
    {
        // Arrange
        const string recipientEmail = "test@example.com";
        const string subject = "Test Subject";
        const string body = "Test Body";

        // Act & Assert - Should not throw any exceptions
        await _emailService.SendEmailAsync(recipientEmail, subject, body);
    }

    [Fact]
    public async Task SendEmailAsync_NullRecipientEmail_ThrowsArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(
            () => _emailService.SendEmailAsync(null, "Subject", "Body"));
    }

    [Fact]
    public async Task SendEmailAsync_EmptySubject_ThrowsArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(
            () => _emailService.SendEmailAsync("test@example.com", "", "Body"));
    }

    [Fact]
    public async Task SendEmailAsync_EmptyBody_ThrowsArgumentException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentException>(
            () => _emailService.SendEmailAsync("test@example.com", "Subject", ""));
    }
}