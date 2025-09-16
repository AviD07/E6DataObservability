using Confluent.Kafka;
using System;
using System.Threading.Tasks;

public class KafkaProducer : IDisposable
{
    private readonly IProducer<Null, string> _producer;
    private readonly string _topic;

    public KafkaProducer(string bootstrapServers, string topic)
    {
        var config = new ProducerConfig
        {
            BootstrapServers = bootstrapServers,
            Acks = Acks.All,
            MessageSendMaxRetries = 3,
            // linger and batch settings can be tuned for throughput
            LingerMs = 5
        };
        _producer = new ProducerBuilder<Null, string>(config).Build();
        _topic = topic;
    }

    public Task<DeliveryResult<Null, string>?> ProduceAsync(string message)
    {
        try
        {
            return _producer.ProduceAsync(_topic, new Message<Null, string> { Value = message });
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Kafka Produce Exception] {ex.Message}");
            return Task.FromException<DeliveryResult<Null, string>?>(ex);
        }
    }

    public void Dispose()
    {
        try
        {
            _producer.Flush(TimeSpan.FromSeconds(5));
            _producer.Dispose();
        }
        catch { }
    }
}
