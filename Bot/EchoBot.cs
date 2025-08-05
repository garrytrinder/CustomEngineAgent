using Microsoft.Agents.Builder;
using Microsoft.Agents.Builder.App;
using Microsoft.Agents.Builder.State;
using Microsoft.Agents.Core.Models;
using System.Net.Http.Headers;
using System.Text.Json;

namespace CustomEngineAgent.Bot;

public class EchoBot(AgentApplicationOptions options) : AgentApplication(options)
{
    [Route(RouteType = RouteType.Activity, Type = ActivityTypes.Message, Rank = RouteRank.Last, SignInHandlers = "me")]
    protected async Task OnMessageAsync(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken)
    {
        await turnContext.StreamingResponse.QueueInformativeUpdateAsync("Working on it...", cancellationToken: cancellationToken);
        var accessToken = await UserAuthorization.GetTurnTokenAsync(turnContext, UserAuthorization.DefaultHandlerName, cancellationToken: cancellationToken);
        var givenName = await GetGivenName(accessToken, cancellationToken);
        int count = turnState.Conversation.IncrementMessageCount();
        turnContext.StreamingResponse.QueueTextChunk($"({count}) ");
        turnContext.StreamingResponse.QueueTextChunk($"Hello {givenName}. ");
        turnContext.StreamingResponse.QueueTextChunk("You said: ");
        turnContext.StreamingResponse.QueueTextChunk($"{turnContext.Activity.Text} [1]");
        turnContext.StreamingResponse.EnableGeneratedByAILabel = true;
        var citation = new Citation(turnContext.Activity.Text, "Citation", "https://www.microsoft.com");
        turnContext.StreamingResponse.AddCitations([citation]);
        await turnContext.StreamingResponse.EndStreamAsync(cancellationToken);
    }

    [Route(RouteType = RouteType.Message, Type = ActivityTypes.Message, Text = "-reset")]
    protected async Task Reset(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken) {
        await UserAuthorization.SignOutUserAsync(turnContext, turnState, "me", cancellationToken: cancellationToken);
        turnState.Conversation.SetValue("count", 0);
        await turnContext.SendActivityAsync("State and auth reset", cancellationToken: cancellationToken);
    }

    private static async Task<string> GetGivenName(string accessToken, CancellationToken cancellationToken)
    {
        using HttpClient client = new();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        HttpResponseMessage response = await client.GetAsync("https://graph.microsoft.com/v1.0/me", cancellationToken);
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        return JsonDocument.Parse(content).RootElement.GetProperty("givenName").GetString();
    }
}