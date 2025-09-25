using System;
using System.Collections.Generic;

public class EventGenerator
{
    private readonly Random _rand = new Random();
    private readonly string[] _eventTypes = new[] { "EXECUTION", "START", "COMPLETED", "FAILED", "SCALE" };

    public IEnumerable<QueryEvent> GenerateBatch(int queriesPerSecond, bool includeErrors = false, bool largeQueries = false)
    {
        for (int i = 0; i < queriesPerSecond; i++)
        {
            int eventCount = largeQueries && _rand.NextDouble() < 0.1 ? 20 : 5;

            for (int j = 0; j < eventCount; j++)
            {
                yield return new QueryEvent
                {
                    query_id = Guid.NewGuid().ToString(),
                    timestamp = DateTime.UtcNow.ToString("o"),
                    event_type = _eventTypes[_rand.NextInt64(0,4)],
                    query_text = "SELECT * FROM table WHERE id=" + _rand.Next(1000),
                    metadata = new Metadata
                    {
                        user_id = "user_" + _rand.Next(1, 100),
                        database = "db" + _rand.Next(1, 5),
                        duration_ms = _rand.Next(50, 2000),
                        rows_affected = _rand.Next(0, 100),
                        error = includeErrors && _rand.NextDouble() < 0.1 ? "Simulated query error" : null
                    },
                    payload = new { stage = "processing", seq = j }
                };
            }
        }
    }
}
