namespace JapaneseMasteryBackendDotNet.Realtime;

public class MetricsTracker
{
    private long _packetsIn = 0;
    private long _packetsOut = 0;
    private int _activeSockets = 0;
    private double _averageRttMs = 0;
    private long _rttSamples = 0;
    private readonly object _rttLock = new();

    public long PacketsIn => Interlocked.Read(ref _packetsIn);
    public long PacketsOut => Interlocked.Read(ref _packetsOut);
    public int ActiveSockets => _activeSockets;
    public double AverageRttMs => _averageRttMs;

    public void IncrementIn() => Interlocked.Increment(ref _packetsIn);
    public void IncrementOut() => Interlocked.Increment(ref _packetsOut);
    public void SocketConnected() => Interlocked.Increment(ref _activeSockets);
    public void SocketDisconnected() => Interlocked.Decrement(ref _activeSockets);

    public void RecordRtt(double rttMs)
    {
        lock (_rttLock)
        {
            _rttSamples++;
            _averageRttMs = _averageRttMs == 0 ? rttMs : (_averageRttMs * 0.8 + rttMs * 0.2);
        }
    }

    public string GetSummary()
    {
        return $"Sockets: {_activeSockets} | Pkts In: {PacketsIn} | Pkts Out: {PacketsOut} | Avg RTT: {_averageRttMs:F1}ms";
    }
}
