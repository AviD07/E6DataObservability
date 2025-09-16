public enum LoadProfile
{
    Steady,    // 100 QPS => 500 EPS
    Burst,     // 2x QPS for 60 sec
    Outage,    // 30s pause
    Recovery   // Resume normal
}
