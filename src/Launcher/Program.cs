// =============================================================================
// WinBreathe Native Self-Contained Executable Host (Program.cs)
// Embeds PowerShell Engine, GUI, Config & Brand Assets inside a single .exe
// Automatically extracts embedded runtime on standalone execution and supports
// both GUI mode (double-click) and CLI mode (when arguments are passed).
// =============================================================================

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("WinBreathe - Windows 11 Memory & Latency Optimizer")]
[assembly: AssemblyDescription("Hardware-Adaptive Windows 11 Memory & Latency Optimizer for 4-16 GB RAM PCs, HDDs & AI Stacks")]
[assembly: AssemblyCompany("WinBreathe Open Source Project")]
[assembly: AssemblyProduct("WinBreathe")]
[assembly: AssemblyCopyright("Copyright (c) 2026 WinBreathe Contributors (MIT License)")]
#if V1_BUILD
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]
#else
[assembly: AssemblyVersion("2.1.0.0")]
[assembly: AssemblyFileVersion("2.1.0.0")]
#endif

namespace WinBreatheHost
{
    internal static class NativeMethods
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern bool AttachConsole(int dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern bool FreeConsole();

        internal const int ATTACH_PARENT_PROCESS = -1;
    }

    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
#if V1_BUILD
                string versionTag = "v1.1.0";
#else
                string versionTag = "v2.1.0";
#endif
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                string runtimeDir = PrepareRuntimeDirectory(exeDir, versionTag);

                bool isCliMode = (args != null && args.Length > 0);
#if V1_BUILD
                string guiScript = Path.Combine(runtimeDir, "scripts", "WinBreatheGUI.ps1");
                string cliScript = Path.Combine(runtimeDir, "scripts", "Win11LowRamOptimizer.ps1");
#else
                string guiScript = Path.Combine(runtimeDir, "src", "WinBreathe.GUI.ps1");
                string cliScript = Path.Combine(runtimeDir, "src", "WinBreathe.ps1");
#endif

                if (isCliMode && (args[0].Equals("-GUI", StringComparison.OrdinalIgnoreCase) || args[0].Equals("/GUI", StringComparison.OrdinalIgnoreCase)))
                {
                    isCliMode = false;
                }

                if (!isCliMode)
                {
                    // Launch Native WinForms Dark GUI
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = string.Format("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{0}\"", guiScript),
                        WorkingDirectory = runtimeDir,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                    using (Process p = Process.Start(psi))
                    {
                        if (p != null)
                        {
                            p.WaitForExit();
                            return p.ExitCode;
                        }
                    }
                    return 0;
                }
                else
                {
                    NativeMethods.AttachConsole(NativeMethods.ATTACH_PARENT_PROCESS);
                    StringBuilder argBuilder = new StringBuilder();
                    argBuilder.AppendFormat("-NoProfile -ExecutionPolicy Bypass -File \"{0}\"", cliScript);
                    foreach (string a in args)
                    {
                        if (a.Contains(" "))
                            argBuilder.AppendFormat(" \"{0}\"", a.Replace("\"", "\\\""));
                        else
                            argBuilder.AppendFormat(" {0}", a);
                    }

                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = argBuilder.ToString(),
                        WorkingDirectory = runtimeDir,
                        UseShellExecute = false
                    };
                    using (Process p = Process.Start(psi))
                    {
                        if (p != null)
                        {
                            p.WaitForExit();
                            return p.ExitCode;
                        }
                    }
                    return 0;
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "WinBreathe encountered a startup error:\n\n" + ex.Message,
                    "WinBreathe Launcher Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                return 1;
            }
        }

        private static string PrepareRuntimeDirectory(string exeDir, string versionTag)
        {
#if !V1_BUILD
            // If running right inside the repository root where src\WinBreathe.GUI.ps1 and config\tweaks.json exist, use it directly
            string localGui = Path.Combine(exeDir, "src", "WinBreathe.GUI.ps1");
            string localCfg = Path.Combine(exeDir, "config", "tweaks.json");
            if (File.Exists(localGui) && File.Exists(localCfg))
            {
                return exeDir;
            }
#endif
            // Otherwise, extract embedded resources into %LocalAppData%\WinBreathe\runtime\<versionTag>
            string baseLocal = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WinBreathe",
                "runtime",
                versionTag
            );

            Assembly asm = Assembly.GetExecutingAssembly();
#if V1_BUILD
            ExtractResource(asm, "Win11LowRamOptimizer.ps1", Path.Combine(baseLocal, "scripts", "Win11LowRamOptimizer.ps1"));
            ExtractResource(asm, "WinBreatheGUI.ps1",        Path.Combine(baseLocal, "scripts", "WinBreatheGUI.ps1"));
#else
            ExtractResource(asm, "WinBreathe.Engine.psm1",   Path.Combine(baseLocal, "src", "WinBreathe.Engine.psm1"));
            ExtractResource(asm, "WinBreathe.ps1",           Path.Combine(baseLocal, "src", "WinBreathe.ps1"));
            ExtractResource(asm, "WinBreathe.GUI.ps1",       Path.Combine(baseLocal, "src", "WinBreathe.GUI.ps1"));
            ExtractResource(asm, "tweaks.json",              Path.Combine(baseLocal, "config", "tweaks.json"));
            ExtractResource(asm, "logo.png",                 Path.Combine(baseLocal, "assets", "logo.png"));
            ExtractResource(asm, "icon.ico",                 Path.Combine(baseLocal, "assets", "icon.ico"));
#endif
            return baseLocal;
        }

        private static void ExtractResource(Assembly asm, string resourceName, string targetPath)
        {
            string dir = Path.GetDirectoryName(targetPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            using (Stream s = asm.GetManifestResourceStream(resourceName))
            {
                if (s == null) return;
                using (FileStream fs = new FileStream(targetPath, FileMode.Create, FileAccess.Write, FileShare.Read))
                {
                    s.CopyTo(fs);
                }
            }
        }
    }
}
