using System.Collections.Concurrent;
using LazyScan.Core;

namespace LazyScan.App.Scanning;

/// <summary>
/// The one thread that touches WIA Automation (wiaaut.dll) in this process: a background STA
/// thread that runs WIA work one item at a time, in the order it was asked for. Every WIA object
/// is created, used and released on it, by every WIA backend and session alike.
///
/// WIA Automation keeps state shared by the whole process, and its objects are apartment-threaded:
/// used from several STA threads at once, objects created on one thread are handed to another and
/// are released or torn down under it (RPC_E_DISCONNECTED, "COM object that has been separated from
/// its underlying RCW", and at worst an access violation inside CoCreateInstance, which ends the
/// process). One thread, one item at a time, rules that out.
/// </summary>
internal static class WiaApartment
{
    private static readonly BlockingCollection<Action> Queue = [];
    private static readonly Lazy<Thread> Worker = new(Start, LazyThreadSafetyMode.ExecutionAndPublication);
    private static readonly ConcurrentDictionary<int, bool> UsedOn = new();
    private static int _inUse;
    private static int _mostInUse;
    private static long _uses;
    private static long _completed;
    private static int _timedOut;
    private static string? _hungDevice;

    /// <summary>The managed id of the WIA thread (it is started if it was not yet).</summary>
    internal static int ThreadId => Worker.Value.ManagedThreadId;

    /// <summary>How many WIA work items have finished (harnesses).</summary>
    internal static long Completed => Interlocked.Read(ref _completed);

    /// <summary>The managed ids of every thread that has created WIA objects (<see cref="Use"/>; harnesses).</summary>
    internal static IReadOnlyCollection<int> ThreadsThatUsedWia => [.. UsedOn.Keys];

    /// <summary>The most <see cref="Use"/> scopes that were ever open at the same time (harnesses).</summary>
    internal static int MostUsingWiaAtOnce => Volatile.Read(ref _mostInUse);

    /// <summary>How many <see cref="Use"/> scopes have been opened (harnesses).</summary>
    internal static long Uses => Interlocked.Read(ref _uses);

    /// <summary>
    /// Marks where WIA objects are created (an enumeration, a session connecting to its device)
    /// until it is disposed, noting the thread and how many such places are busy at once. It
    /// changes nothing; harnesses read it to check that WIA is used on one thread, one at a time,
    /// whatever the code that queued the work.
    /// </summary>
    internal static UseScope Use()
    {
        UsedOn.TryAdd(Environment.CurrentManagedThreadId, true);
        Interlocked.Increment(ref _uses);
        int inUse = Interlocked.Increment(ref _inUse);
        int most;
        while (inUse > (most = Volatile.Read(ref _mostInUse))
               && Interlocked.CompareExchange(ref _mostInUse, inUse, most) != most)
        {
        }
        return new UseScope();
    }

    internal readonly struct UseScope : IDisposable
    {
        public void Dispose() => Interlocked.Decrement(ref _inUse);
    }

    /// <summary>
    /// Runs <paramref name="work"/> on the WIA thread after the work asked for before it. The task
    /// completes (or faults with its exception) off that thread, so a continuation never holds it up.
    /// </summary>
    public static Task<T> Run<T>(Func<T> work)
    {
        var done = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        _ = Worker.Value;
        Queue.Add(() =>
        {
            try
            {
                done.SetResult(work());
            }
            catch (Exception e)
            {
                done.SetException(e);
            }
        });
        return done.Task;
    }

    /// <summary>
    /// Like <see cref="Run{T}(Func{T})"/>, for a call that must not hold a scanner up for good. When
    /// <paramref name="work"/> has not finished <paramref name="timeout"/> after it began on the WIA
    /// thread, the task faults with a "not responding" <see cref="ScanException"/>. The call itself
    /// cannot be stopped, so the thread stays busy until it returns; every timed call asked for
    /// meanwhile fails at once, naming the device that is stuck, instead of waiting behind it.
    /// </summary>
    public static async Task<T> Run<T>(Func<T> work, TimeSpan timeout, string deviceName)
    {
        if (Volatile.Read(ref _timedOut) > 0) throw NotResponding(Volatile.Read(ref _hungDevice) ?? deviceName);
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var abandoned = false;
        var task = Run(() =>
        {
            if (Volatile.Read(ref abandoned)) throw new OperationCanceledException();
            started.SetResult();
            return work();
        });
        try
        {
            await started.Task.WaitAsync(timeout).ConfigureAwait(false);
            return await task.WaitAsync(timeout).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            if (!started.Task.IsCompleted)
            {
                // Still queued behind other work: drop it rather than run it late.
                Volatile.Write(ref abandoned, true);
                throw NotResponding(Volatile.Read(ref _hungDevice) ?? deviceName);
            }
            Volatile.Write(ref _hungDevice, deviceName);
            Interlocked.Increment(ref _timedOut);
            _ = task.ContinueWith(_ => Interlocked.Decrement(ref _timedOut), TaskScheduler.Default);
            throw NotResponding(deviceName);
        }
    }

    private static ScanException NotResponding(string deviceName) =>
        ScanException.SessionFailed(() => Loc.T("{0} is not responding. Turn it off and on again, then try again.", deviceName));

    private static Thread Start()
    {
        var thread = new Thread(Loop)
        {
            IsBackground = true,
            Name = "WIA",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return thread;
    }

    private static void Loop()
    {
        // Waiting for the next item on an STA thread pumps COM messages, as the apartment requires.
        foreach (var item in Queue.GetConsumingEnumerable())
        {
            try
            {
                item();
            }
            catch (Exception e)
            {
                // Run catches the work's exceptions; nothing else may end the WIA thread.
                System.Diagnostics.Trace.TraceWarning($"WIA work failed: {e.Message}");
            }
            finally
            {
                Interlocked.Increment(ref _completed);
            }
        }
    }
}
