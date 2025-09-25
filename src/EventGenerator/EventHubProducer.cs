using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using System;
using System.Text;
using System.Threading.Tasks;

public class EventHubProducer : IAsyncDisposable
{
    private readonly EventHubProducerClient _producer;

    public EventHubProducer(string connectionString, string eventHubName)
    {
        _producer = new EventHubProducerClient(connectionString, eventHubName);
    }

    public async Task SendAsync(string message)
    {
        try
        {
            using EventDataBatch eventBatch = await _producer.CreateBatchAsync();

            if (!eventBatch.TryAdd(new EventData(Encoding.UTF8.GetBytes(message))))
            {
                Console.WriteLine("Message too large for Event Hub batch, skipping...");
                return;
            }

            await _producer.SendAsync(eventBatch);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[EventHubProducer] Error while sending: {ex.Message}");
        }
    }

    public async ValueTask DisposeAsync()
    {
        await _producer.DisposeAsync();
    }
}
