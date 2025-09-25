using System;
using System.Text.Json;

public class QueryEvent
{
    public string query_id { get; set; }
    public string timestamp { get; set; }
    public string event_type { get; set; }
    public string query_text { get; set; }
    public Metadata metadata { get; set; }
    public object payload { get; set; }

    public string ToJson() => JsonSerializer.Serialize(this);
}

public class Metadata
{
    public string user_id { get; set; }
    public string database { get; set; }
    public int duration_ms { get; set; }
    public int rows_affected { get; set; }
    public string error { get; set; }
}
