using System;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    class EventHubConfig
    {
        public string ConnectionString { get; set; }
        public string HubName { get; set; }
    }

    static async Task Main(string[] args)
    {
        // Default to "steady" if no arguments are provided
        string mode = args.Length > 0 ? args[0].ToLower() : "steady";

        Console.WriteLine($"Starting Event Generator in '{mode}' mode...");

        LoadProfile profile = mode switch
        {
            "recovery" => LoadProfile.Recovery,
            "burst" => LoadProfile.Burst,
            "steady" => LoadProfile.Steady,
            "outage" => LoadProfile.Outage,
            _ => throw new ArgumentException($"Unknown mode '{mode}'. Valid options: steady, outage, burst, recovery")
        };

        int baseQps = args.Length > 1 ? int.Parse(args[1]) : 100;
        int durationSeconds = args.Length > 2 ? int.Parse(args[2]) : 60;

        // Event Hub args (optional)
        string configFile = "eventhub.config.json";
        EventHubConfig ehConfig = null;

        if (args.Length > 4) // user explicitly passed EH config
        {
            ehConfig = new EventHubConfig
            {
                ConnectionString = args[3],
                HubName = args[4]
            };
            File.WriteAllText(configFile, JsonSerializer.Serialize(ehConfig));
            Console.WriteLine($"[INFO] Saved Event Hub config to {configFile}");
        }
        else if (File.Exists(configFile))
        {
            ehConfig = JsonSerializer.Deserialize<EventHubConfig>(File.ReadAllText(configFile));
            Console.WriteLine($"[INFO] Loaded Event Hub config from {configFile}");
        }
        else
        {
            Console.WriteLine("Please provide the Event hub configs for the first run. Usage :  docker run --rm event-generator <mode> <qps> <event flow time> <EventhubConnectionString> <EventHubName>");
            throw new ArgumentException("Event Hub config missing. Pass ConnectionString + HubName once, or provide eventhub.config.json");
        }

        var generator = new EventGenerator();
        // var kafkaProducer = new KafkaProducer(kafkaBroker, kafkaTopic);
        var ehProducer = new EventHubProducer(ehConfig.ConnectionString, ehConfig.HubName);

        Console.WriteLine($"BaseQPS={baseQps}, Duration={durationSeconds}s");

        int qps = profile switch
        {
            LoadProfile.Steady => baseQps,
            LoadProfile.Burst => baseQps * 2,
            LoadProfile.Outage => 0,
            LoadProfile.Recovery => baseQps,
            _ => baseQps
        };

        for (int sec = 0; sec < durationSeconds; sec++)
        {
            var events = generator.GenerateBatch(qps, includeErrors: true, largeQueries: true);

            // Fire off all sends in parallel
            var tasks = new List<Task>();
            foreach (var e in events)
            {
                string json = e.ToJson();
                if (qps > 0)
                {
                    // Send to Event Hub (or Kafka, if enabled)
                    tasks.Add(ehProducer.SendAsync(json));
                    // tasks.Add(kafkaProducer.ProduceAsync(json));
                }
            }

            // Wait for all sends for this second
            await Task.WhenAll(tasks);

            Console.WriteLine($"[{sec}] [{DateTime.UtcNow}] Profile={profile}, QPS={qps}, EventsSent={events.Count()}");

            // Keep steady pacing
            await Task.Delay(1000);
        }

        Console.WriteLine("Event generation complete.");
    }
}
