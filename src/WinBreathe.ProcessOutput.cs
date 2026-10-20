using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Threading;

// Native event callbacks do not need a PowerShell runspace. The UI only drains
// completed lines; it never waits on EndOfStream or ReadLine in a timer tick.
public sealed class WBProcessOutput : IDisposable
{
    private readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
    private readonly Process process;
    private int closedStreams;
    public WBProcessOutput(Process child)
    {
        process = child;
        process.OutputDataReceived += Receive;
        process.ErrorDataReceived += Receive;
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
    }
    private void Receive(object sender, DataReceivedEventArgs args)
    {
        if (args.Data == null) Interlocked.Increment(ref closedStreams);
        else lines.Enqueue(args.Data);
    }
    public bool Complete { get { return process.HasExited && Volatile.Read(ref closedStreams) == 2 && lines.IsEmpty; } }
    public string ReadAvailable()
    {
        string line;
        return lines.TryDequeue(out line) ? line : null;
    }
    public void Dispose()
    {
        process.OutputDataReceived -= Receive;
        process.ErrorDataReceived -= Receive;
    }
}
