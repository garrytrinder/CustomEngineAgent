using Microsoft.Agents.Builder;
using Microsoft.Agents.Builder.App;
using Microsoft.Agents.Builder.State;
using Microsoft.Agents.Core.Models;

namespace CustomEngineAgent.Bot;

public class EchoBot : AgentApplication
{
    public EchoBot(AgentApplicationOptions options) : base(options) { }

    [Route(RouteType = RouteType.Activity, Type = ActivityTypes.Message, Rank = RouteRank.Last)]
    protected async Task OnMessageAsync(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken)
    {
        await turnContext.StreamingResponse.QueueInformativeUpdateAsync("Working on it...", cancellationToken: cancellationToken);
        int count = turnState.Conversation.IncrementMessageCount();
        turnContext.StreamingResponse.QueueTextChunk($"({count}) ");
        turnContext.StreamingResponse.QueueTextChunk("You said: ");
        turnContext.StreamingResponse.QueueTextChunk($"{turnContext.Activity.Text} [1]");
        await turnContext.StreamingResponse.EndStreamAsync(cancellationToken);
    }
}
