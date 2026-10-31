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
using System.Security.AccessControl;
using System.Security.Principal;
using System.Windows.Forms;

[assembly: AssemblyTitle("WinBreathe - Adaptive Windows Memory Watch and Relief")]
[assembly: AssemblyDescription("Memory pressure monitoring and controlled relief for Windows and protected development workloads")]
[assembly: AssemblyCompany("WinBreathe Open Source Project")]
[assembly: AssemblyProduct("WinBreathe")]
[assembly: AssemblyCopyright("Copyright (c) 2026 WinBreathe Contributors (MIT License)")]
#if V1_BUILD
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]
#else
[assembly: AssemblyVersion("2.3.0.0")]
[assembly: AssemblyFileVersion("2.3.0.0")]
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
            string runtimeDir = null;
            try
            {
#if V1_BUILD
                string versionTag = "v1.1.0";
#else
                string versionTag = "v2.3.0";
#endif
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                runtimeDir = PrepareRuntimeDirectory(exeDir, versionTag);

                bool isCliMode = (args != null && args.Length > 0);
#if V1_BUILD
                string guiScript = Path.Combine(runtimeDir, "scripts", "WinBreatheGUI.ps1");
                string cliScript = Path.Combine(runtimeDir, "scripts", "Win11LowRamOptimizer.ps1");
#else
                string guiScript = Path.Combine(runtimeDir, "src", "WinBreathe.GUI.ps1");
                string cliScript = Path.Combine(runtimeDir, "src", "WinBreathe.ps1");
#endif

                if (isCliMode && args.Length == 1 && (args[0].Equals("-GUI", StringComparison.OrdinalIgnoreCase) || args[0].Equals("/GUI", StringComparison.OrdinalIgnoreCase)))
                {
                    isCliMode = false;
                }

                if (!isCliMode)
                {
                    // Launch Native WinForms Dark GUI
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
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
                    foreach (string a in args) argBuilder.Append(" ").Append(QuoteWindowsArgument(a));

                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"),
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
                if (args != null && args.Length > 0)
                {
                    // Headless checks must report an error code, not leave a
                    // modal dialog blocking the user's desktop.
                    Console.Error.WriteLine("WinBreathe startup failed: " + ex.Message);
                    return 1;
                }
                MessageBox.Show(
                    "WinBreathe encountered a startup error:\n\n" + ex.Message,
                    "WinBreathe Launcher Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                return 1;
            }
            finally
            {
                if (runtimeDir != null)
                {
                    try { Directory.Delete(runtimeDir, true); }
                    catch { /* A still-open file may leave this private runtime for manual cleanup. */ }
                }
            }
        }

        // Implements Windows argv quoting, including quotes, tabs and trailing slashes.
        internal static string QuoteWindowsArgument(string value)
        {
            StringBuilder b = new StringBuilder("\"");
            int slashes = 0;
            foreach (char c in value)
            {
                if (c == '\\') { slashes++; continue; }
                if (c == '\"') { b.Append('\\', slashes * 2 + 1); b.Append(c); slashes = 0; continue; }
                b.Append('\\', slashes); slashes = 0; b.Append(c);
            }
            b.Append('\\', slashes * 2); b.Append('\"');
            return b.ToString();
        }

        private static void AssertProtectedDirectory(string path)
        {
            DirectoryInfo current = new DirectoryInfo(path);
            while (current != null)
            {
                if ((current.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Linked runtime path is not allowed.");
                current = current.Parent;
            }
            DirectorySecurity acl = Directory.GetAccessControl(path);
            string[] trusted = { "S-1-5-18", "S-1-5-32-544", "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464" };
            if (Array.IndexOf(trusted, acl.GetOwner(typeof(SecurityIdentifier)).Value) < 0) throw new IOException("Untrusted runtime parent owner.");
            FileSystemRights writes = FileSystemRights.Write | FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
            foreach (FileSystemAccessRule rule in acl.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType == AccessControlType.Allow && (rule.PropagationFlags & PropagationFlags.InheritOnly) == 0 && (rule.FileSystemRights & writes) != 0 && Array.IndexOf(trusted, rule.IdentityReference.Value) < 0)
                    throw new IOException("Untrusted runtime parent write access.");
            }
        }

        private static string PrepareRuntimeDirectory(string exeDir, string versionTag)
        {
            // Never execute neighboring scripts/config or overwrite a shared runtime.
            // Elevated runs extract only embedded resources into an admin-only directory.
            WindowsIdentity identity = WindowsIdentity.GetCurrent();
            bool elevated = new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
            string parent = elevated ? Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) : Path.GetTempPath();
            if (elevated) AssertProtectedDirectory(parent);
            string baseLocal = Path.Combine(parent, "WinBreathe-runtime-" + versionTag + "-" + Guid.NewGuid().ToString("N"));
            DirectorySecurity security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            SecurityIdentifier owner = elevated ? new SecurityIdentifier("S-1-5-32-544") : identity.User;
            security.SetOwner(owner);
            security.AddAccessRule(new FileSystemAccessRule(owner, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
            security.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier("S-1-5-18"), FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
            if (elevated) Directory.CreateDirectory(baseLocal, security);
            // A restricted/app-container token also needs the package ACLs
            // inherited from its own temporary directory. Replacing those with
            // only the user SID prevents even that process from extracting files.
            // Unelevated files are never reused by an elevated launch.
            else Directory.CreateDirectory(baseLocal);
            Assembly asm = Assembly.GetExecutingAssembly();
#if V1_BUILD
            ExtractResource(asm, "Win11LowRamOptimizer.ps1", Path.Combine(baseLocal, "scripts", "Win11LowRamOptimizer.ps1"));
            ExtractResource(asm, "WinBreatheGUI.ps1", Path.Combine(baseLocal, "scripts", "WinBreatheGUI.ps1"));
#else
            ExtractResource(asm, "WinBreathe.ProcessOutput.cs", Path.Combine(baseLocal, "src", "WinBreathe.ProcessOutput.cs"));
            ExtractResource(asm, "WinBreathe.Engine.psm1", Path.Combine(baseLocal, "src", "WinBreathe.Engine.psm1"));
            ExtractResource(asm, "WinBreathe.MemoryWatch.ps1", Path.Combine(baseLocal, "src", "WinBreathe.MemoryWatch.ps1"));
            ExtractResource(asm, "WinBreathe.MemoryRelief.ps1", Path.Combine(baseLocal, "src", "WinBreathe.MemoryRelief.ps1"));
            ExtractResource(asm, "WinBreathe.MemoryRelief.cs", Path.Combine(baseLocal, "src", "WinBreathe.MemoryRelief.cs"));
            ExtractResource(asm, "WinBreathe.ps1", Path.Combine(baseLocal, "src", "WinBreathe.ps1"));
            ExtractResource(asm, "WinBreathe.GUI.ps1", Path.Combine(baseLocal, "src", "WinBreathe.GUI.ps1"));
            ExtractResource(asm, "tweaks.json", Path.Combine(baseLocal, "config", "tweaks.json"));
            ExtractResource(asm, "logo.png", Path.Combine(baseLocal, "assets", "logo.png"));
            ExtractResource(asm, "icon.ico", Path.Combine(baseLocal, "assets", "icon.ico"));
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
                if (s == null) throw new IOException("Required embedded resource is missing: " + resourceName);
                using (FileStream fs = new FileStream(targetPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
                {
                    s.CopyTo(fs);
                }
            }
        }
    }
}
