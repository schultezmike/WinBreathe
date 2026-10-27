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
    private int queuedLines;
    private int droppedLines;
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
        else if (Interlocked.Increment(ref queuedLines) <= 2000)
            lines.Enqueue(args.Data.Length > 4096 ? args.Data.Substring(0, 4096) + " [truncated]" : args.Data);
        else { Interlocked.Decrement(ref queuedLines); Interlocked.Increment(ref droppedLines); }
    }
    public bool Complete { get { return process.HasExited && Volatile.Read(ref closedStreams) == 2 && lines.IsEmpty && Volatile.Read(ref droppedLines) == 0; } }
    public string ReadAvailable()
    {
        string line;
        if (lines.TryDequeue(out line)) { Interlocked.Decrement(ref queuedLines); return line; }
        int dropped = Interlocked.Exchange(ref droppedLines, 0);
        return dropped > 0 ? "[WARN] " + dropped + " task output lines were omitted to bound memory use." : null;
    }
    public void Dispose()
    {
        process.OutputDataReceived -= Receive;
        process.ErrorDataReceived -= Receive;
    }
}
