using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

// Native event callbacks do not need a PowerShell runspace. The UI only drains
// completed lines; it never waits on EndOfStream or ReadLine in a timer tick.
public sealed class WBProcessOutput : IDisposable
{
    private readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
    private readonly Process process;
    private int closedStreams;
    private int queuedLines;
    private int droppedLines;
    private volatile bool disposed;
    private readonly Task stdoutPump;
    private readonly Task stderrPump;
    public WBProcessOutput(Process child)
    {
        process = child;
        stdoutPump = Pump(process.StandardOutput);
        stderrPump = Pump(process.StandardError);
    }
    private void Enqueue(string line)
    {
        if(disposed) return;
        if (Interlocked.Increment(ref queuedLines) <= 2000) lines.Enqueue(line);
        else { Interlocked.Decrement(ref queuedLines); Interlocked.Increment(ref droppedLines); }
    }
    private async Task Pump(StreamReader reader)
    {
        // BeginOutputReadLine buffers the WHOLE line before its callback. A
        // faulty child without newlines could bypass the old queue limit.
        char[] chunk = new char[2048];
        StringBuilder line = new StringBuilder(4096);
        bool truncated=false, previousCR=false;
        try {
            int count;
            while((count=await reader.ReadAsync(chunk,0,chunk.Length).ConfigureAwait(false)) > 0) {
                for(int i=0;i<count;i++) {
                    char c=chunk[i];
                    if(c=='\n' && previousCR) { previousCR=false; continue; }
                    if(c=='\r' || c=='\n') {
                        Enqueue(line.ToString()+(truncated ? " [truncated]" : ""));
                        line.Length=0; truncated=false; previousCR=c=='\r';
                    } else {
                        previousCR=false;
                        if(line.Length < 4096) line.Append(c); else truncated=true;
                    }
                }
            }
            if(line.Length > 0 || truncated) Enqueue(line.ToString()+(truncated ? " [truncated]" : ""));
        } catch(IOException) { Enqueue("[WARN] Task output stream could not be read completely."); }
        catch(ObjectDisposedException) { }
        finally { Interlocked.Increment(ref closedStreams); }
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
        // Let pending reads finish draining without retaining further output.
        // Never terminate a child because the display is being disposed.
        disposed=true;
        string ignored;
        while(lines.TryDequeue(out ignored)) Interlocked.Decrement(ref queuedLines);
        Interlocked.Exchange(ref droppedLines,0);
    }
}
