using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

namespace WinBreatheV230 {
    // A retained handle binds validation and trimming to the same process.
    // No terminate/suspend rights, privilege adjustment, or memory limit changes.
    public static class MemoryRelief {
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder path, ref int length);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr h, out long created, out long exited, out long kernel, out long user);
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr token);
        [DllImport("psapi.dll", SetLastError=true)] static extern bool EmptyWorkingSet(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
        delegate bool WindowCallback(IntPtr window, IntPtr data);
        [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback callback, IntPtr data);

        public static string Trim(int pid, long startFileTime, string image, double lastCpuMs) {
            IntPtr handle = OpenProcess(0x1000 | 0x0100, false, pid); // query limited + set quota
            if(handle == IntPtr.Zero) return "Skipped: process unavailable or access denied";
            try {
                long created, exited, kernel, user;
                if(!GetProcessTimes(handle, out created, out exited, out kernel, out user) || created != startFileTime || exited != 0)
                    return "Skipped: process identity changed";
                int length=32768; StringBuilder path=new StringBuilder(length);
                if(!QueryFullProcessImageName(handle, 0, path, ref length) || !String.Equals(path.ToString(), image, StringComparison.OrdinalIgnoreCase))
                    return "Skipped: executable identity unavailable or changed";
                IntPtr token;
                if(!OpenProcessToken(handle, 8, out token)) return "Skipped: owner unavailable";
                try {
                    using(WindowsIdentity owner=new WindowsIdentity(token))
                    using(WindowsIdentity current=WindowsIdentity.GetCurrent()) {
                        if(owner.User == null || current.User == null || owner.User.Value != current.User.Value)
                            return "Skipped: another user's process";
                    }
                } finally { CloseHandle(token); }
                double cpuMs=(kernel+user)/10000.0;
                if(cpuMs < lastCpuMs || cpuMs-lastCpuMs > 100) return "Skipped: process became busy";
                uint foreground; GetWindowThreadProcessId(GetForegroundWindow(), out foreground);
                if(foreground == (uint)pid) return "Skipped: foreground process";
                bool visible=false;
                bool enumerated=EnumWindows(delegate(IntPtr window, IntPtr data) {
                    uint owner; GetWindowThreadProcessId(window, out owner);
                    if(owner == (uint)pid && IsWindowVisible(window)) visible=true;
                    return true;
                }, IntPtr.Zero);
                if(!enumerated || visible) return "Skipped: visible window or window query unavailable";
                return EmptyWorkingSet(handle) ? "Trimmed" : "Skipped: Windows declined relief ("+Marshal.GetLastWin32Error()+")";
            } finally { CloseHandle(handle); }
        }
    }
}
