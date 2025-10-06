using Microsoft.Graph;
using Microsoft.Graph.Models;

namespace GraphEmailService;

public interface IEmailService
{
    Task SendEmailAsync(string recipientEmail, string subject, string body, bool isHtml = false);
    Task SendEmailAsync(IEnumerable<string> recipientEmails, string subject, string body, bool isHtml = false);
}

public class EmailService : IEmailService
{
    private readonly GraphServiceClient _graphServiceClient;

    public EmailService(GraphServiceClient graphServiceClient)
    {
        _graphServiceClient = graphServiceClient ?? throw new ArgumentNullException(nameof(graphServiceClient));
    }

    public async Task SendEmailAsync(string recipientEmail, string subject, string body, bool isHtml = false)
    {
        if (string.IsNullOrWhiteSpace(recipientEmail))
            throw new ArgumentException("Recipient email cannot be null or empty.", nameof(recipientEmail));

        await SendEmailAsync(new[] { recipientEmail }, subject, body, isHtml);
    }

    public async Task SendEmailAsync(IEnumerable<string> recipientEmails, string subject, string body, bool isHtml = false)
    {
        if (recipientEmails == null || !recipientEmails.Any())
            throw new ArgumentException("At least one recipient email is required.", nameof(recipientEmails));

        if (string.IsNullOrWhiteSpace(subject))
            throw new ArgumentException("Subject cannot be null or empty.", nameof(subject));

        if (string.IsNullOrWhiteSpace(body))
            throw new ArgumentException("Body cannot be null or empty.", nameof(body));

        var recipients = recipientEmails.Select(email => new Recipient
        {
            EmailAddress = new EmailAddress
            {
                Address = email
            }
        }).ToList();

        var message = new Message
        {
            Subject = subject,
            Body = new ItemBody
            {
                ContentType = isHtml ? BodyType.Html : BodyType.Text,
                Content = body
            },
            ToRecipients = recipients
        };

        var sendMail = new SendMailRequestBody
        {
            Message = message,
            SaveToSentItems = true
        };

        await _graphServiceClient.Me.SendMail.PostAsync(sendMail);
    }
}